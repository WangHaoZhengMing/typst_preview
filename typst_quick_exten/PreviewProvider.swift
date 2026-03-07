//
//  PreviewProvider.swift
//  typst_quick_exten
//
//  Created by Wanghaozhengming on 1/7/26.
//

import Cocoa
import Quartz
import CryptoKit

class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    

    /*
     Use a QLPreviewProvider to provide data-based previews.
     
     To set up your extension as a data-based preview extension:

     - Modify the extension's Info.plist by setting
       <key>QLIsDataBasedPreview</key>
       <true/>
     
     - Add the supported content types to QLSupportedContentTypes array in the extension's Info.plist.

     - Change the NSExtensionPrincipalClass to this class.
       e.g.
       <key>NSExtensionPrincipalClass</key>
       <string>$(PRODUCT_MODULE_NAME).PreviewProvider</string>
     
     - Implement providePreview(for:)
     */
    
    func parseTypstImports(_ fileURL: URL) -> [(namespace: String, package: String, version: String)] {
        var packages = [(namespace: String, package: String, version: String)]()
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return packages }
        
        let pattern = "@([\\w\\-]+)/([\\w\\-]+)(?::([\\d\\.]+))?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return packages }
        
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: nsRange)
        
        for match in matches {
            guard let nsRange1 = Range(match.range(at: 1), in: content),
                  let nsRange2 = Range(match.range(at: 2), in: content) else { continue }
            let namespace = String(content[nsRange1])
            let package = String(content[nsRange2])
            var version = ""
            if match.range(at: 3).location != NSNotFound, let nsRange3 = Range(match.range(at: 3), in: content) {
                version = String(content[nsRange3])
            }
            packages.append((namespace, package, version))
        }
        return packages
    }
    
    func sharedGroupDirectory() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.typst.preview")
    }

    func isPackageInstalled(namespace: String, package: String, version: String) -> Bool {
        guard let groupDir = sharedGroupDirectory() else { return false }
        let packageDir = groupDir.appendingPathComponent("packages/\(namespace)/\(package)/\(version)")
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: packageDir.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return false
    }

    func requestPackageDownload(missingPackages: [(namespace: String, package: String, version: String)]) {
        guard let groupDir = sharedGroupDirectory() else { return }
        let requestsURL = groupDir.appendingPathComponent("requests.json")
        
        var queue = [[String: Any]]()
        
        if let data = try? Data(contentsOf: requestsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let existingQueue = json["queue"] as? [[String: Any]] {
               queue = existingQueue
        }
        
        for pkg in missingPackages {
            let item: [String: Any] = [
                "namespace": pkg.namespace,
                "package": pkg.package,
                "version": pkg.version,
                "time": Date().timeIntervalSince1970
            ]
            let exists = queue.contains { dict in
                return (dict["namespace"] as? String) == pkg.namespace &&
                       (dict["package"] as? String) == pkg.package &&
                       (dict["version"] as? String) == pkg.version
            }
            if !exists {
                queue.append(item)
            }
        }
        
        let jsonDict: [String: Any] = ["queue": queue]
        if let newData = try? JSONSerialization.data(withJSONObject: jsonDict, options: .prettyPrinted) {
            try? newData.write(to: requestsURL, options: .atomic)
            
            // Post notification
            let distributedNotificationCenter = DistributedNotificationCenter.default()
            distributedNotificationCenter.postNotificationName(NSNotification.Name("TypstPackageDownloadRequest"), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }

    func generateCacheHash(fileURL: URL) -> String? {
        guard let contentData = try? Data(contentsOf: fileURL) else { return nil }
        let hash = SHA256.hash(data: contentData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let file = request.fileURL
        
        let packages = parseTypstImports(file)
        let missing = packages.filter { !isPackageInstalled(namespace: $0.namespace, package: $0.package, version: $0.version) }
        
        if !missing.isEmpty {
            requestPackageDownload(missingPackages: missing)
            
            let html = """
            <html><body>
            <h2>Downloading typst packages...</h2>
            <ul>
                \(missing.map { "<li>@\($0.namespace)/\($0.package):\($0.version)</li>" }.joined(separator: "\n"))
            </ul>
            </body></html>
            """
            
            return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 600)) { reply in
                return html.data(using: .utf8) ?? Data()
            }
        }
        
        // Setup shared group path for libtypst
        if let groupPath = sharedGroupDirectory()?.path {
            groupPath.withCString { cPath in
                typst_set_shared_group_path(cPath)
            }
        }
        
        guard let cacheHash = generateCacheHash(fileURL: file),
              let groupDir = sharedGroupDirectory() else {
            return QLPreviewReply(dataOfContentType: .pdf, contentSize: CGSize(width: 800, height: 800)) { _ in return Data() }
        }
        
        let cacheDir = groupDir.appendingPathComponent("cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        let cachedPDFURL = cacheDir.appendingPathComponent("\(cacheHash).pdf")
        
        if FileManager.default.fileExists(atPath: cachedPDFURL.path) {
            // Return cached PDF
            return QLPreviewReply(fileURL: cachedPDFURL)
        }
        
        // Compile typst
        let inputFile = file.path
        let outputFile = cachedPDFURL.path
        
        let result = inputFile.withCString { cInput in
            outputFile.withCString { cOutput in
                return typst_compile_file(cInput, cOutput)
            }
        }
        
        if result == Success {
            return QLPreviewReply(fileURL: cachedPDFURL)
        } else {
            // Compilation failed, fallback error message
            let errMsg = String(cString: typst_result_message(result))
            let html = "<html><body><h2>Compilation Error</h2><pre>\(errMsg)</pre></body></html>"
            return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 600)) { _ in
                return html.data(using: .utf8) ?? Data()
            }
        }
    }
}
