//
//  SecurityScopedPDFLoader.swift
//  SlideRemote
//
//  Reads PDFs from the file picker, which live outside the app sandbox.
//

import Foundation
import PDFKit

struct SecurityScopedPDFLoader: PDFLoading {
    /// The whole PDF is read into memory; the limit avoids exhausting it with a huge file.
    static let defaultMaxFileSize = 200 * 1_024 * 1_024

    let maxFileSize: Int

    init(maxFileSize: Int = defaultMaxFileSize) {
        self.maxFileSize = maxFileSize
    }

    func load(from url: URL) throws(PDFLoadError) -> PDFDocument {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxFileSize {
            throw .fileTooLarge
        }

        let data: Data
        do {
            // Reads everything into memory while access is open.
            data = try Data(contentsOf: url)
        } catch {
            throw .readFailed(reason: error.localizedDescription)
        }

        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
            throw .invalidDocument
        }
        return pdf
    }
}
