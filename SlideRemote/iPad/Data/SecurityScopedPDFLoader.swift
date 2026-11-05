//
//  SecurityScopedPDFLoader.swift
//  SlideRemote
//
//  Lê PDFs vindos do seletor de arquivos, que ficam fora do sandbox do app.
//

import Foundation
import PDFKit

struct SecurityScopedPDFLoader: PDFLoading {
    func load(from url: URL) throws(PDFLoadError) -> PDFDocument {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            // Lê tudo para a memória enquanto o acesso está aberto.
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
