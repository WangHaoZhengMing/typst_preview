//
//  PreviewViewController.swift
//  typst_quick_exten
//
//  Created by Wanghaozhengming on 1/7/26.
//

import Cocoa
import Quartz
import PDFKit

class PreviewViewController: NSViewController, QLPreviewingController {
    
    private var pdfView: PDFView!
    
    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        super.loadView()
        
        // 创建 PDF 预览视图
        pdfView = PDFView()
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        view.addSubview(pdfView)
        
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
    
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let pdfURL = try self?.compileTypstToPDF(inputURL: url)
                guard let pdfURL = pdfURL else {
                    throw TypstPreviewError.unknown
                }
                guard let pdfDocument = PDFDocument(url: pdfURL) else {
                    throw TypstPreviewError.pdfLoadFailed
                }
                DispatchQueue.main.async {
                    self?.pdfView.document = pdfDocument
                    handler(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    handler(error)
                }
            }
        }
    }

    /// 使用内置 C 接口编译 Typst 为 PDF
    private func compileTypstToPDF(inputURL: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".pdf")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        let result = typst_compile_file(inputURL.path, outputURL.path)
        if result != Success {
            let messagePtr = typst_result_message(result)
            let message = messagePtr != nil ? String(cString: messagePtr!) : "Unknown error"
            throw TypstPreviewError.compileFailed(result, message)
        }
        
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw TypstPreviewError.pdfNotGenerated
        }
        return outputURL
    }
}

// MARK: - Error Types

enum TypstPreviewError: LocalizedError {
    case compileFailed(TypstResult, String)
    case pdfNotGenerated
    case pdfLoadFailed
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .compileFailed(let code, let message):
            return "Typst compile failed (\(code)): \(message)"
        case .pdfNotGenerated:
            return "PDF file was not generated"
        case .pdfLoadFailed:
            return "Failed to load generated PDF"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
