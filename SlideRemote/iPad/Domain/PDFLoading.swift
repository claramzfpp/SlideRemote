//
//  PDFLoading.swift
//  SlideRemote
//
//  Contract for loading the PDF chosen by the user.
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
            "Could not open this PDF."
        case .fileTooLarge:
            "This PDF is too large to open."
        case .readFailed(let reason):
            "Error reading the file: \(reason)"
        }
    }
}
