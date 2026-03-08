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
                        subtitle: self.statusSubtitle(for: transitiveMissing.count, noun: "dependency")
                    ), nil)
                    return
                }

                handler(self.placeholderReply(for: request, title: "Compile error", subtitle: self.summarizedMessage(message)), nil)
            } catch {
                handler(self.placeholderReply(for: request, title: "Typst", subtitle: self.summarizedMessage(error.localizedDescription)), nil)
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
            let cornerRadius: CGFloat = min(rect.width, rect.height) * 0.08
            let background = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    NSColor(calibratedRed: 0.05, green: 0.13, blue: 0.22, alpha: 1.0).cgColor,
                    NSColor(calibratedRed: 0.08, green: 0.42, blue: 0.60, alpha: 1.0).cgColor,
                ] as CFArray,
                locations: [0, 1]
            )

            if let background = background {
                context.drawLinearGradient(background, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: rect.maxX, y: 0), options: [])
            } else {
                context.setFillColor(NSColor.darkGray.cgColor)
                context.fill(rect)
            }

            let glowRect = rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.14)
            context.setFillColor(NSColor.white.withAlphaComponent(0.05).cgColor)
            context.fillEllipse(in: glowRect)

            let cardWidth = min(rect.width * 0.74, 320)
            let cardHeight = min(rect.height * 0.72, 240)
            let cardRect = CGRect(
                x: (rect.width - cardWidth) * 0.5,
                y: (rect.height - cardHeight) * 0.5,
                width: cardWidth,
                height: cardHeight
            )

            let cardPath = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: NSColor.black.withAlphaComponent(0.22).cgColor)
            context.addPath(cardPath)
            context.setFillColor(NSColor.white.cgColor)
            context.fillPath()
            context.restoreGState()

            let foldWidth = cardRect.width * 0.20
            let foldHeight = cardRect.height * 0.16
            let foldPath = CGMutablePath()
            foldPath.move(to: CGPoint(x: cardRect.maxX - foldWidth, y: cardRect.maxY))
            foldPath.addLine(to: CGPoint(x: cardRect.maxX, y: cardRect.maxY))
            foldPath.addLine(to: CGPoint(x: cardRect.maxX, y: cardRect.maxY - foldHeight))
            foldPath.closeSubpath()
            context.addPath(foldPath)
            context.setFillColor(NSColor(calibratedWhite: 0.93, alpha: 1.0).cgColor)
            context.fillPath()

            let badgeRect = CGRect(x: cardRect.minX + 18, y: cardRect.maxY - 52, width: 38, height: 24)
            let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
            context.addPath(badgePath)
            context.setFillColor(NSColor(calibratedRed: 0.09, green: 0.44, blue: 0.82, alpha: 1.0).cgColor)
            context.fillPath()

            NSGraphicsContext.saveGraphicsState()
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.current = graphicsContext

            let badgeAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: min(24, rect.width * 0.08), weight: .bold),
                .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1.0),
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: min(14, rect.width * 0.05), weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1.0),
            ]
            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: min(11, rect.width * 0.04), weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1.0),
            ]

            let badgeString = NSAttributedString(string: "T", attributes: badgeAttributes)
            let titleString = NSAttributedString(string: title, attributes: titleAttributes)
            let subtitleString = NSAttributedString(string: subtitle, attributes: subtitleAttributes)
            let footerString = NSAttributedString(string: "Typst Quick Look", attributes: footerAttributes)

            badgeString.draw(in: CGRect(x: badgeRect.minX + 13, y: badgeRect.minY + 4, width: 12, height: 16))
            titleString.draw(in: CGRect(x: cardRect.minX + 18, y: cardRect.maxY - 96, width: cardRect.width - 36, height: 30))
            subtitleString.draw(in: CGRect(x: cardRect.minX + 18, y: cardRect.minY + 52, width: cardRect.width - 36, height: cardRect.height - 120))
            footerString.draw(in: CGRect(x: cardRect.minX + 18, y: cardRect.minY + 18, width: cardRect.width - 36, height: 16))
            NSGraphicsContext.restoreGraphicsState()
            return true
        })
    }

    private func summarizedMessage(_ message: String) -> String {
        let lowered = message.lowercased()
        if lowered.contains("file not found") && lowered.contains("/packages/") {
            return "A required package version is missing"
        }
        if lowered.contains("math") {
            return "Math rendering is not available yet"
        }
        if lowered.contains("image") || lowered.contains("asset") {
            return "External assets are blocked by sandbox rules"
        }
        if lowered.contains("sandbox") || lowered.contains("access denied") {
            return "Sandbox restrictions prevented rendering"
        }
        if lowered.contains("network") {
            return "Network access is unavailable here"
        }
        let compact = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? "Preview could not be generated" : String(compact.prefix(72))
    }

    private func statusSubtitle(for count: Int, noun: String) -> String {
        if count == 1 {
            return "1 \(noun) pending"
        }
        return "\(count) \(noun)s pending"
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
