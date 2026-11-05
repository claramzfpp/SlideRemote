//
//  PDFLoading.swift
//  SlideRemote
//
//  Contrato para carregar o PDF escolhido pelo usuário.
//

import Foundation
import PDFKit

protocol PDFLoading {
    func load(from url: URL) throws(PDFLoadError) -> PDFDocument
}

enum PDFLoadError: LocalizedError {
    case invalidDocument
    case fileTooLarge
    case readFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            "Não foi possível abrir esse PDF."
        case .fileTooLarge:
            "Esse PDF é grande demais para abrir."
        case .readFailed(let reason):
            "Erro ao ler o arquivo: \(reason)"
        }
    }
}
