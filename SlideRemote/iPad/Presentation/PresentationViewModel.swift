//
//  PresentationViewModel.swift
//  SlideRemote
//
//  Orquestra o iPad: carrega o PDF e aplica os comandos recebidos do iPhone.
//

import Foundation
import PDFKit
import Combine

@MainActor
final class PresentationViewModel: ObservableObject {
    @Published private(set) var document: PDFDocument?
    @Published private(set) var presentation: Presentation?
    @Published private(set) var isConnected = false
    @Published private(set) var loadError: String?

    private let receiver: CommandReceiving
    private let pdfLoader: PDFLoading

    init(receiver: CommandReceiving, pdfLoader: PDFLoading) {
        self.receiver = receiver
        self.pdfLoader = pdfLoader

        receiver.onCommand = { [weak self] command in
            // Sem PDF carregado não há o que avançar.
            self?.presentation?.apply(command)
        }
        receiver.onConnectionChange = { [weak self] isConnected in
            self?.isConnected = isConnected
        }
        receiver.start()
    }

    func loadPDF(from url: URL) {
        do {
            let pdf = try pdfLoader.load(from: url)
            document = pdf
            presentation = Presentation(pageCount: pdf.pageCount)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func closePresentation() {
        document = nil
        presentation = nil
    }
}
