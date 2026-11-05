//
//  RemoteView.swift
//  SlideRemote
//
//  Tela do iPhone: escolhe o iPad, pede o código de pareamento e então mostra as setas dos slides.
//

import SwiftUI

struct RemoteView: View {
    @StateObject private var viewModel = RemoteViewModel(
        sender: MultipeerRemoteSender(),
        movementSource: WatchConnectivityManager.shared
    )
    @State private var codeInput = ""

    var body: some View {
        VStack {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.2))
        .onAppear { viewModel.startListeningToWatch() }
        .onDisappear { viewModel.stopListeningToWatch() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .searching:
            peerList
        case .connecting:
            connecting
        case .enteringCode(let attemptsLeft):
            codeEntry(attemptsLeft: attemptsLeft)
        case .verifying:
            ProgressView("Verificando código...")
        case .paired:
            pairedControls
        }
    }

    private var peerList: some View {
        VStack(spacing: 16) {
            if let notice = viewModel.notice {
                Text(notice)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            if viewModel.peers.isEmpty {
                Label("Procurando iPad...", systemImage: "ipad.slash")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                List(viewModel.peers) { peer in
                    Button {
                        codeInput = ""
                        viewModel.select(peer)
                    } label: {
                        Label(peer.name, systemImage: "ipad")
                    }
                }
            }
        }
    }

    private var connecting: some View {
        VStack(spacing: 16) {
            ProgressView("Aguardando o iPad permitir...")
            Button("Cancelar", role: .cancel) { viewModel.cancelConnection() }
        }
    }

    private func codeEntry(attemptsLeft: Int?) -> some View {
        VStack(spacing: 16) {
            Text("Digite o código de 6 dígitos mostrado no iPad")
                .multilineTextAlignment(.center)
            TextField("000000", text: $codeInput)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .onChange(of: codeInput) { _, newValue in
                    let digits = String(newValue.filter(\.isASCIIDigit).prefix(PairingCode.length))
                    if digits != newValue { codeInput = digits }
                }
            if let error = viewModel.codeError {
                Text(error).foregroundStyle(.red)
            }
            if let attemptsLeft {
                Text("Código incorreto. Tentativas restantes: \(attemptsLeft)")
                    .foregroundStyle(.red)
            }
            Button("Confirmar") { viewModel.submitCode(codeInput) }
                .buttonStyle(.borderedProminent)
            Button("Cancelar", role: .cancel) { viewModel.cancelConnection() }
        }
        .padding()
    }

    private var pairedControls: some View {
        VStack {
            Label("iPad conectado", systemImage: "ipad")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
                .padding(.top)

            Spacer()

            HStack {
                ArrowButton(
                    image: Image(systemName: "arrow.left"),
                    accessibilityLabel: "Slide Anterior"
                ) {
                    viewModel.previous()
                }

                Spacer()

                ArrowButton(
                    image: Image(systemName: "arrow.right"),
                    accessibilityLabel: "Próximo Slide"
                ) {
                    viewModel.next()
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical)

            Spacer()
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

struct ArrowButton: View {
    var image: Image
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            image
                .resizable()
                .frame(width: 80, height: 80)
                .padding(24)
                .foregroundColor(.white)
                .background {
                    Circle()
                }
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    RemoteView()
}

#Preview {
    ArrowButton(
        image: Image(systemName: "arrow.left"),
        accessibilityLabel: "Slide Anterior"
    ) {
        print("pra trás")
    }
}
