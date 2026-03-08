import AppKit
import CryptoKit
import PDFKit
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    private let packageImportPattern = "@([\\w\\-]+)/([\\w\\-]+)(?::([\\d\\.]+))?"

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let fileURL = request.fileURL
        let accessed = fileURL.startAccessingSecurityScopedResource()

        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                if accessed {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            let packages = self.parseTypstImports(fileURL)
            let missingPackages = packages.filter {
                !self.isPackageInstalled(namespace: $0.namespace, package: $0.package, version: $0.version)
            }

            if !missingPackages.isEmpty {
                self.requestPackageDownload(missingPackages: missingPackages)
                handler(self.placeholderReply(
                    for: request,
                    title: "Downloading packages",
                    subtitle: missingPackages.map { "@\($0.namespace)/\($0.package):\($0.version)" }.joined(separator: ", ")
                ), nil)
                return
            }

            do {
                let pdfURL = try self.compileTypstToPDF(inputURL: fileURL)
                handler(self.renderedReply(for: request, pdfURL: pdfURL), nil)
            } catch let ThumbnailError.compileFailed(_, message) {
                let transitiveMissing = self.missingPackagesFromCompileMessage(message).filter {
                    !self.isPackageInstalled(namespace: $0.namespace, package: $0.package, version: $0.version)
                }

                if !transitiveMissing.isEmpty {
                    self.requestPackageDownload(missingPackages: transitiveMissing)
                    handler(self.placeholderReply(
                        for: request,
                        title: "Downloading dependencies",
                        subtitle: transitiveMissing.map { "@\($0.namespace)/\($0.package):\($0.version)" }.joined(separator: ", ")
                    ), nil)
                    return
                }

                handler(self.placeholderReply(for: request, title: "Typst", subtitle: message), nil)
            } catch {
                handler(self.placeholderReply(for: request, title: "Typst", subtitle: error.localizedDescription), nil)
            }
        }
    }

    private func parseTypstImports(_ fileURL: URL) -> [(namespace: String, package: String, version: String)] {
        var packages = [(namespace: String, package: String, version: String)]()
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return packages }

        guard let regex = try? NSRegularExpression(pattern: packageImportPattern) else { return packages }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)

        for match in regex.matches(in: content, options: [], range: range) {
            guard let namespaceRange = Range(match.range(at: 1), in: content),
                  let packageRange = Range(match.range(at: 2), in: content) else { continue }

            let namespace = String(content[namespaceRange])
            let package = String(content[packageRange])
            let version: String
            if match.range(at: 3).location != NSNotFound,
               let versionRange = Range(match.range(at: 3), in: content) {
                version = String(content[versionRange])
            } else {
                version = ""
            }
            packages.append((namespace: namespace, package: package, version: version))
        }

        return packages
    }

    private func sharedGroupDirectory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.typst.preview")
    }

    private func isPackageInstalled(namespace: String, package: String, version: String) -> Bool {
        guard let groupDir = sharedGroupDirectory() else { return false }
        let packageDir = groupDir.appendingPathComponent("packages/\(namespace)/\(package)/\(version)")

        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: packageDir.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func requestPackageDownload(missingPackages: [(namespace: String, package: String, version: String)]) {
        let pendingURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("pending_downloads.json")
        let queue = missingPackages.map { pkg in
            ["namespace": pkg.namespace, "package": pkg.package, "version": pkg.version]
        }
        let json: [String: Any] = ["queue": queue, "timestamp": Date().timeIntervalSince1970]

        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? data.write(to: pendingURL)
        }
    }

    private func missingPackagesFromCompileMessage(_ message: String) -> [(namespace: String, package: String, version: String)] {
        let pattern = #"/packages/([^/]+)/([^/]+)/([^/)"\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        let matches = regex.matches(in: message, options: [], range: range)
        var packages: [(namespace: String, package: String, version: String)] = []
        var seen = Set<String>()

        for match in matches {
            guard let namespaceRange = Range(match.range(at: 1), in: message),
                  let packageRange = Range(match.range(at: 2), in: message),
                  let versionRange = Range(match.range(at: 3), in: message) else { continue }

            let namespace = String(message[namespaceRange])
            let package = String(message[packageRange])
            let version = String(message[versionRange])
            let key = "\(namespace)/\(package):\(version)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            packages.append((namespace: namespace, package: package, version: version))
        }

        return packages
    }

    private func generateCacheHash(fileURL: URL) -> String? {
        guard let contentData = try? Data(contentsOf: fileURL) else { return nil }
        let hash = SHA256.hash(data: contentData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func compileTypstToPDF(inputURL: URL) throws -> URL {
        if let groupPath = sharedGroupDirectory()?.path {
            groupPath.withCString { cPath in
                typst_set_shared_group_path(cPath)
            }
        }

        guard let cacheHash = generateCacheHash(fileURL: inputURL) else {
            throw ThumbnailError.unknown
        }

        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("typst_thumbnail_cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let outputURL = cacheDir.appendingPathComponent("\(cacheHash).pdf")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        let result = inputURL.path.withCString { cInput in
            outputURL.path.withCString { cOutput in
                typst_compile_file(cInput, cOutput)
            }
        }

        if result == Success {
            return outputURL
        }

        let messagePtr = typst_result_message(result)
        let message = messagePtr != nil ? String(cString: messagePtr!) : "Unknown error"
        throw ThumbnailError.compileFailed(result, message)
    }

    private func renderedReply(for request: QLFileThumbnailRequest, pdfURL: URL) -> QLThumbnailReply? {
        guard let document = CGPDFDocument(pdfURL as CFURL),
              let page = document.page(at: 1) else {
            return placeholderReply(for: request, title: "Typst", subtitle: "Failed to load PDF")
        }

        let pageRect = page.getBoxRect(.mediaBox)
        let targetSize = fittedSize(for: pageRect.size, maximum: request.maximumSize)

        return QLThumbnailReply(contextSize: targetSize, drawing: { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: targetSize))

            let scale = min(targetSize.width / pageRect.width, targetSize.height / pageRect.height)
            let drawWidth = pageRect.width * scale
            let drawHeight = pageRect.height * scale
            let originX = (targetSize.width - drawWidth) * 0.5
            let originY = (targetSize.height - drawHeight) * 0.5

            context.saveGState()
            context.translateBy(x: originX, y: originY)
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(page)
            context.restoreGState()
            return true
        })
    }

    private func placeholderReply(for request: QLFileThumbnailRequest, title: String, subtitle: String) -> QLThumbnailReply? {
        let size = request.maximumSize
        return QLThumbnailReply(contextSize: size, drawing: { context in
            let rect = CGRect(origin: .zero, size: size)
            let background = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    NSColor(calibratedRed: 0.11, green: 0.17, blue: 0.27, alpha: 1.0).cgColor,
                    NSColor(calibratedRed: 0.12, green: 0.36, blue: 0.54, alpha: 1.0).cgColor,
                ] as CFArray,
                locations: [0, 1]
            )

            if let background = background {
                context.drawLinearGradient(background, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: rect.maxX, y: 0), options: [])
            } else {
                context.setFillColor(NSColor.darkGray.cgColor)
                context.fill(rect)
            }

            let iconRect = CGRect(x: 24, y: rect.height - 92, width: 44, height: 56)
            context.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
            context.fill(iconRect)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
            context.stroke(iconRect, width: 1)

            NSGraphicsContext.saveGraphicsState()
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.current = graphicsContext

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]

            let titleString = NSAttributedString(string: title, attributes: titleAttributes)
            let subtitleString = NSAttributedString(string: subtitle, attributes: subtitleAttributes)

            titleString.draw(in: CGRect(x: 84, y: rect.height - 78, width: rect.width - 104, height: 28))
            subtitleString.draw(in: CGRect(x: 24, y: 24, width: rect.width - 48, height: rect.height - 120))
            NSGraphicsContext.restoreGraphicsState()
            return true
        })
    }

    private func fittedSize(for originalSize: CGSize, maximum: CGSize) -> CGSize {
        guard originalSize.width > 0, originalSize.height > 0 else { return maximum }
        let scale = min(maximum.width / originalSize.width, maximum.height / originalSize.height)
        let scaleValue = min(scale, 1)
        return CGSize(width: max(1, originalSize.width * scaleValue), height: max(1, originalSize.height * scaleValue))
    }
}

private enum ThumbnailError: LocalizedError {
    case compileFailed(TypstResult, String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .compileFailed(let code, let message):
            return "Typst compile failed (\(code)): \(message)"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
