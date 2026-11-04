//
//  PresentationView.swift
//  SlideRemote
//
//  Tela do iPad: escolhe o PDF e mostra o slide controlado pelo iPhone.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct PresentationView: View {
    @StateObject private var receiver = PresentationReceiver()
    @State private var isImporterPresented = false

    var body: some View {
        Group {
            if let document = receiver.document, let presentation = receiver.presentation {
                slideScreen(document: document, presentation: presentation)
            } else {
                emptyScreen
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                receiver.loadPDF(from: url)
            }
        }
    }

    // MARK: - Sem PDF

    private var emptyScreen: some View {
        VStack(spacing: 24) {
            Text("SlideRemote")
                .font(.largeTitle.bold())

            Button("Escolher PDF") { isImporterPresented = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            if let error = receiver.loadError {
                Text(error)
                    .foregroundStyle(.red)
            }

            connectionLabel
        }
        .padding()
    }

    // MARK: - Apresentando

    private func slideScreen(document: PDFDocument, presentation: Presentation) -> some View {
        ZStack(alignment: .bottom) {
            PDFKitView(document: document, pageIndex: presentation.currentIndex)
                .ignoresSafeArea()

            HStack(spacing: 16) {
                Text("\(presentation.currentPage) / \(presentation.pageCount)")
                    .monospacedDigit()

                if !receiver.isConnected {
                    Label("iPhone desconectado", systemImage: "iphone.slash")
                }

                Button("Fechar", systemImage: "xmark.circle") { receiver.closePresentation() }
                    .labelStyle(.iconOnly)
            }
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(.bottom, 12)
        }
        .background(Color.black)
    }

    private var connectionLabel: some View {
        Label(
            receiver.isConnected ? "iPhone conectado" : "Aguardando iPhone...",
            systemImage: receiver.isConnected ? "iphone.radiowaves.left.and.right" : "iphone.slash"
        )
        .foregroundStyle(receiver.isConnected ? .green : .secondary)
    }
}

#Preview {
    PresentationView()
}
