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
    @StateObject private var viewModel = PresentationViewModel(
        receiver: MultipeerCommandReceiver(),
        pdfLoader: SecurityScopedPDFLoader()
    )
    @State private var isImporterPresented = false

    var body: some View {
        Group {
            if let document = viewModel.document, let presentation = viewModel.presentation {
                slideScreen(document: document, presentation: presentation)
            } else {
                emptyScreen
            }
        }
        .alert(
            "Permitir \(viewModel.pendingInvitation ?? "") a controlar os slides?",
            isPresented: invitationBinding
        ) {
            Button("Permitir") { viewModel.respondToInvitation(accept: true) }
            Button("Recusar", role: .cancel) { viewModel.respondToInvitation(accept: false) }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                viewModel.loadPDF(from: url)
            }
        }
    }

    private var invitationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingInvitation != nil },
            // Fechar o alerta sem escolher conta como recusa; após uma resposta o convite já não existe.
            set: { if !$0 { viewModel.respondToInvitation(accept: false) } }
        )
    }

    // MARK: - Sem PDF

    private var emptyScreen: some View {
        VStack(spacing: 24) {
            Text("SlideRemote")
                .font(.largeTitle.bold())

            Button("Escolher PDF") { isImporterPresented = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            if let error = viewModel.loadError {
                Text(error)
                    .foregroundStyle(.red)
            }

            connectionLabel
            pairingCodeView
            disconnectButton
        }
        .padding()
    }

    // MARK: - Apresentando

    private func slideScreen(document: PDFDocument, presentation: Presentation) -> some View {
        ZStack(alignment: .bottom) {
            PDFKitView(document: document, pageIndex: presentation.currentIndex)
                .ignoresSafeArea()

            if codeToShow != nil {
                pairingCodeView
                    .padding(24)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity)
            }

            HStack(spacing: 16) {
                Text("\(presentation.currentPage) / \(presentation.pageCount)")
                    .monospacedDigit()

                if !viewModel.isAuthenticated {
                    Label(viewModel.isConnected ? "Aguardando código no iPhone" : "iPhone desconectado",
                          systemImage: "iphone.slash")
                }

                if canDisconnectPhone {
                    Button("Desconectar iPhone", systemImage: "iphone.slash") { viewModel.disconnectPhone() }
                        .labelStyle(.iconOnly)
                }

                Button("Fechar", systemImage: "xmark.circle") { viewModel.closePresentation() }
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

    /// Disponível enquanto houver um iPhone aprovado, conectado ou não.
    private var canDisconnectPhone: Bool {
        viewModel.isConnected || viewModel.pairingCode != nil
    }

    @ViewBuilder
    private var disconnectButton: some View {
        if canDisconnectPhone {
            Button("Desconectar iPhone", systemImage: "iphone.slash", role: .destructive) {
                viewModel.disconnectPhone()
            }
        }
    }

    private var connectionLabel: some View {
        Label(connectionText, systemImage: viewModel.isAuthenticated ? "iphone.radiowaves.left.and.right" : "iphone.slash")
            .foregroundStyle(viewModel.isAuthenticated ? .green : .secondary)
    }

    private var connectionText: String {
        if viewModel.isAuthenticated { return "iPhone conectado" }
        return viewModel.isConnected ? "Aguardando código no iPhone" : "Aguardando iPhone..."
    }

    /// Só aparece com o peer conectado e ainda não autenticado.
    private var codeToShow: PairingCode? {
        viewModel.isConnected && !viewModel.isAuthenticated ? viewModel.pairingCode : nil
    }

    @ViewBuilder
    private var pairingCodeView: some View {
        if let code = codeToShow {
            let spaced = String(code.value.prefix(3)) + " " + String(code.value.suffix(3))
            VStack(spacing: 8) {
                Text("Digite no iPhone:")
                    .font(.title3)
                Text(spaced)
                    .font(.system(size: 72, weight: .bold, design: .monospaced))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Digite no iPhone o código \(code.value.map(String.init).joined(separator: " "))")
        }
    }
}

#Preview {
    PresentationView()
}
