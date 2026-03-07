import Foundation
import OSLog
import SwiftUI
import Darwin

private func realUserHomeDirectory() -> String {
    guard let pwd = getpwuid(getuid()), let home = pwd.pointee.pw_dir else {
        return "/Users/\(NSUserName())"
    }
    return String(cString: home)
}

class DownloaderDaemon: ObservableObject {
    private let groupIdentifier = "group.typst.preview"
    private let extensionBundleIdentifier = "test.typst-preview.typst-quick-exten"
    private var isDownloading = false
    private let logger = Logger(subsystem: "com.typst.preview", category: "daemon")
    private var pollTimer: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "com.typst.preview.daemon.poll")
    private var pollCount: UInt64 = 0
    private var lastProcessedRequestID: String?
    private let packageImportPattern = "@([\\w\\-]+)/([\\w\\-]+)(?::([\\d\\.]+))?"

    init() {
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.checkPendingDownloads()
        }
        timer.resume()
        pollTimer = timer
        pollQueue.async { [weak self] in
            self?.checkPendingDownloads()
        }
        logger.notice("DownloaderDaemon started, polling every 2 seconds.")
    }

    deinit {
        pollTimer?.cancel()
    }

    // The QL extension writes to its OWN private sandbox container.
    // The host app reads it using the absolute-path read-only exception entitlement.
    private func pendingDownloadsURL() -> URL {
        let userHome = realUserHomeDirectory()
        return URL(fileURLWithPath: userHome)
            .appendingPathComponent("Library/Containers/\(extensionBundleIdentifier)/Data/pending_downloads.json")
    }
    
    func checkPendingDownloads() {
        let pendingURL = pendingDownloadsURL()
        pollCount += 1

        if access(pendingURL.path, R_OK) != 0 {
            let code = errno
            if code == EACCES || code == EPERM {
                logger.error("Pending downloads path is not readable: \(pendingURL.path, privacy: .public), errno \(code).")
                return
            }
        }

        if pollCount % 15 == 1 {
            logger.notice("Polling pending downloads at \(pendingURL.path, privacy: .public)")
        }

        guard FileManager.default.fileExists(atPath: pendingURL.path) else {
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: pendingURL)
        } catch {
            logger.error("Failed to read pending downloads file: \(error.localizedDescription, privacy: .public)")
            return
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.error("Pending downloads file has unexpected JSON shape.")
                return
            }
            json = parsed
        } catch {
            logger.error("Failed to parse pending downloads file: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard let queue = json["queue"] as? [[String: Any]], !queue.isEmpty else {
            return
        }

        let timestamp = json["timestamp"] as? Double ?? 0
        let requestID = makeRequestID(timestamp: timestamp, queue: queue)
        guard requestID != lastProcessedRequestID else {
            return
        }

        guard !isDownloading else {
            return
        }

        lastProcessedRequestID = requestID

        logger.notice("Found \(queue.count) pending download request(s).")
        processQueue(queue)
    }
    
    func downloadPackages(_ packages: [(namespace: String, package: String, version: String)]) {
        let queue = packages.map { pkg -> [String: Any] in
            return ["namespace": pkg.namespace, "package": pkg.package, "version": pkg.version]
        }
        processQueue(queue)
    }
    
    private func processQueue(_ queue: [[String: Any]]) {
        guard !isDownloading else { return }
        isDownloading = true
        
        Task {
            var remainingQueue = queue
            var seenPackages = Set<String>()

            while let first = remainingQueue.first {
                remainingQueue.removeFirst()

                guard let currentPackageKey = packageKey(for: first), !seenPackages.contains(currentPackageKey) else {
                    continue
                }
                seenPackages.insert(currentPackageKey)

                guard let packageDir = await ensurePackageInstalled(packageInfo: first) else {
                    continue
                }

                let dependencies = packageDependencies(in: packageDir)
                for dependency in dependencies {
                    guard let dependencyKey = packageKey(for: dependency), !seenPackages.contains(dependencyKey) else {
                        continue
                    }
                    remainingQueue.append(dependency)
                }
            }
            
            self.pollQueue.async {
                self.isDownloading = false
            }
        }
    }

    private func packageKey(for packageInfo: [String: Any]) -> String? {
        guard let namespace = packageInfo["namespace"] as? String,
              let package = packageInfo["package"] as? String,
              let version = packageInfo["version"] as? String else { return nil }
        return "\(namespace)/\(package):\(version)"
    }

    private func packageDirectory(namespace: String, package: String, version: String) -> URL? {
        guard let groupDir = sharedGroupDirectory() else { return nil }
        return groupDir
            .appendingPathComponent("packages")
            .appendingPathComponent(namespace)
            .appendingPathComponent(package)
            .appendingPathComponent(version)
    }

    private func ensurePackageInstalled(packageInfo: [String: Any]) async -> URL? {
        guard let namespace = packageInfo["namespace"] as? String,
              let package = packageInfo["package"] as? String,
              let version = packageInfo["version"] as? String,
              let packageDir = packageDirectory(namespace: namespace, package: package, version: version) else {
            return nil
        }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: packageDir.path, isDirectory: &isDir), isDir.boolValue {
            return packageDir
        }

        let installed = await download(packageInfo: packageInfo)
        return installed ? packageDir : nil
    }

    private func packageDependencies(in packageDir: URL) -> [[String: Any]] {
        guard let regex = try? NSRegularExpression(pattern: packageImportPattern) else {
            return []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: packageDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var dependencies: [String: [String: Any]] = [:]

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "typ" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            for match in regex.matches(in: content, options: [], range: range) {
                guard let namespaceRange = Range(match.range(at: 1), in: content),
                      let packageRange = Range(match.range(at: 2), in: content) else {
                    continue
                }

                let namespace = String(content[namespaceRange])
                let package = String(content[packageRange])
                guard match.range(at: 3).location != NSNotFound,
                      let versionRange = Range(match.range(at: 3), in: content) else {
                    continue
                }

                let version = String(content[versionRange])
                let key = "\(namespace)/\(package):\(version)"
                dependencies[key] = [
                    "namespace": namespace,
                    "package": package,
                    "version": version,
                ]
            }
        }

        return dependencies.values.sorted {
            (packageKey(for: $0) ?? "") < (packageKey(for: $1) ?? "")
        }
    }

    private func makeRequestID(timestamp: Double, queue: [[String: Any]]) -> String {
        let normalizedQueue = queue.map { item in
            let namespace = item["namespace"] as? String ?? ""
            let package = item["package"] as? String ?? ""
            let version = item["version"] as? String ?? ""
            return "\(namespace)/\(package):\(version)"
        }.sorted().joined(separator: "|")
        return "\(timestamp)|\(normalizedQueue)"
    }
    
    private func sharedGroupDirectory() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    private func download(packageInfo: [String: Any]) async -> Bool {
        guard let namespace = packageInfo["namespace"] as? String,
              let package = packageInfo["package"] as? String,
              let version = packageInfo["version"] as? String else { return false }
        
        guard let groupDir = sharedGroupDirectory() else { return false }
        
        // Target: packages/namespace/package/version/
        let packageBaseDir = groupDir
            .appendingPathComponent("packages")
            .appendingPathComponent(namespace)
            .appendingPathComponent(package)
            .appendingPathComponent(version)
            
        let tempDownloadURL = groupDir.appendingPathComponent("temp_\(package)_\(version).tar.gz")
        
        let urlString = "https://packages.typst.org/\(namespace)/\(package)-\(version).tar.gz"
        guard let url = URL(string: urlString) else { return false }
        
        logger.notice("Starting download for @\(namespace)/\(package):\(version)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.error("Failed to download @\(namespace)/\(package):\(version), status \(status).")
                return false
            }
            try data.write(to: tempDownloadURL)
            
            try FileManager.default.createDirectory(at: packageBaseDir, withIntermediateDirectories: true, attributes: nil)
            
            // Unpack tar.gz using native Process / tar command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", tempDownloadURL.path, "-C", packageBaseDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                logger.error("tar extraction failed for @\(namespace)/\(package):\(version), exit code \(process.terminationStatus).")
                try? FileManager.default.removeItem(at: tempDownloadURL)
                return false
            }
            
            try FileManager.default.removeItem(at: tempDownloadURL)
            logger.notice("Successfully installed @\(namespace)/\(package):\(version)")
            return true
        } catch {
            logger.error("Error during download/extraction: \(error.localizedDescription)")
            // Cleanup on failure
            try? FileManager.default.removeItem(at: tempDownloadURL)
            return false
        }
    }
}
