//
//  RemoteView.swift
//  SlideRemote
//
//  iPhone screen: picks the iPad, asks for the pairing code and then shows the slide arrows.
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
        // After a wrong code the field comes back empty, to avoid resending the same guess by accident.
        .onChange(of: viewModel.phase) { _, newPhase in
            if case .enteringCode = newPhase { codeInput = "" }
        }
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
            ProgressView(viewModel.isResuming ? "Resuming connection..." : "Verifying code...")
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
                Label("Searching for iPad...", systemImage: "ipad.slash")
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
            ProgressView("Waiting for the iPad to allow...")
            Button("Cancel", role: .cancel) { viewModel.cancelConnection() }
        }
    }

    private func codeEntry(attemptsLeft: Int?) -> some View {
        VStack(spacing: 16) {
            Text("Enter the 6-digit code shown on the iPad")
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
                Text("Incorrect code. Attempts left: \(attemptsLeft)")
                    .foregroundStyle(.red)
            }
            Button("Confirmar") { viewModel.submitCode(codeInput) }
                .buttonStyle(.borderedProminent)
            Button("Cancel", role: .cancel) { viewModel.cancelConnection() }
        }
        .padding()
        //TODO: open the keyboard
    }

    private var pairedControls: some View {
        VStack {
            Label("iPad connected", systemImage: "ipad")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
                .padding(.top)

            Spacer()

            HStack {
                ArrowButton(
                    image: Image(systemName: "arrow.left"),
                    accessibilityLabel: "Previous Slide"
                ) {
                    viewModel.previous()
                }

                Spacer()

                ArrowButton(
                    image: Image(systemName: "arrow.right"),
                    accessibilityLabel: "Next Slide"
                ) {
                    viewModel.next()
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical)

            Spacer()
        }
        .onAppear {
            // this screen should be always on during the presentation, if it is not, will lose the iPad session
            UIApplication.shared.isIdleTimerDisabled = true
            AppLog.connectivity.info("Idle timer disabled. Keeping screen awake for core app activity.")
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            AppLog.connectivity.info("Idle timer re-enabled. System can now put screen to sleep.")
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
        accessibilityLabel: "Previous Slide"
    ) {
        // preview: no action
    }
}
