//
//  RemoteViewModel.swift
//  SlideRemote
//
//  Drives pairing with the iPad and, after it, wires the screen to the commands and to the Watch's movements.
//

import Combine
import Foundation

enum PairingPhase: Equatable {
    case searching
    case connecting(peerName: String)
    case enteringCode(attemptsLeft: Int?)
    case verifying
    case paired
}

@MainActor
final class RemoteViewModel: ObservableObject {
    @Published private(set) var phase: PairingPhase = .searching
    @Published private(set) var peers: [DiscoveredPeer]
    /// Notice shown in the search after a failure (lockout, drop, declined invitation).
    @Published private(set) var notice: String?
    /// `true` while resuming a previous session without asking for the code.
    @Published private(set) var isResuming = false
    /// Format error of the typed code.
    @Published private(set) var codeError: String?

    private let sender: RemoteCommandSending
    private let movementSource: MovementSource
    private var cancellables = Set<AnyCancellable>()
    /// Reconnect credentials by iPad name, in memory only: they disappear when the app closes.
    private var credentials: [String: HexToken] = [:]
    private var currentPeerName: String?

    init(sender: RemoteCommandSending, movementSource: MovementSource) {
        self.sender = sender
        self.movementSource = movementSource
        self.peers = sender.discoveredPeers

        sender.discoveredPeersPublisher
            .sink { [weak self] in self?.peers = $0 }
            .store(in: &cancellables)

        sender.isConnectedPublisher
            .dropFirst()
            .sink { [weak self] in self?.connectionChanged(isConnected: $0) }
            .store(in: &cancellables)

        sender.onMessage = { [weak self] in self?.handle($0) }
    }

    // MARK: - Pairing

    func select(_ peer: DiscoveredPeer) {
        guard phase == .searching else { return }
        notice = nil
        codeError = nil
        currentPeerName = peer.name
        phase = .connecting(peerName: peer.name)
        sender.connect(to: peer)
    }

    func cancelConnection() {
        guard phase != .searching else { return }
        sender.disconnect()
        isResuming = false
        phase = .searching
    }

    func submitCode(_ input: String) {
        guard case .enteringCode = phase else { return }
        guard let code = PairingCode(input) else {
            codeError = "Enter the 6 digits"
            return
        }
        codeError = nil
        phase = .verifying
        sender.send(.pair(code))
    }

    private func connectionChanged(isConnected: Bool) {
        switch (phase, isConnected) {
        case (.connecting(let name), true):
            if credentials[name] != nil {
                // Already paired with this iPad in this run: tries to resume without asking for the code.
                isResuming = true
                phase = .verifying
                sender.send(.resumeRequest)
            } else {
                phase = .enteringCode(attemptsLeft: nil)
            }
        case (.connecting, false):
            fallBackToSearching(notice: "The iPad declined or did not respond")
        case (.searching, _), (_, true):
            break
        case (_, false):
            fallBackToSearching(notice: "Connection lost")
        }
    }

    private func handle(_ message: RemoteMessage) {
        switch message {
        case .pairingResult(let result): handlePairingResult(result)
        case .credential(let token): store(token)
        case .resumeChallenge(let nonce): answer(nonce)
        case .resumeRejected: resumeWasRejected()
        case .command, .pair, .resumeRequest, .resumeProof:
            break // messages from the iPhone to the iPad; ignored if they come back
        }
    }

    private func handlePairingResult(_ result: PairingResult) {
        guard phase == .verifying else { return }
        switch result {
        case .accepted:
            isResuming = false
            phase = .paired
        case .rejected(let attemptsLeft):
            phase = .enteringCode(attemptsLeft: attemptsLeft)
        case .locked:
            forgetCredential()
            sender.disconnect()
            fallBackToSearching(notice: "Pairing locked. Ask for a new code on the iPad.")
        }
    }

    /// The iPad only issues the credential after authenticating; otherwise it is ignored.
    private func store(_ token: HexToken) {
        guard phase == .verifying || phase == .paired, let name = currentPeerName else { return }
        credentials[name] = token
    }

    /// Answers the challenge with a proof (HMAC); the credential itself is never sent.
    private func answer(_ nonce: HexToken) {
        guard phase == .verifying, isResuming,
              let name = currentPeerName, let credential = credentials[name] else { return }
        sender.send(.resumeProof(ResumeProof.compute(credential: credential, nonce: nonce)))
    }

    private func resumeWasRejected() {
        guard phase == .verifying, isResuming else { return }
        forgetCredential()
        isResuming = false
        codeError = "The previous session expired. Enter the code shown on the iPad."
        phase = .enteringCode(attemptsLeft: nil)
    }

    private func forgetCredential() {
        if let name = currentPeerName { credentials[name] = nil }
    }

    private func fallBackToSearching(notice: String) {
        self.notice = notice
        isResuming = false
        codeError = nil
        phase = .searching
    }

    // MARK: - Control

    func next() { sendCommand(.next) }
    func previous() { sendCommand(.previous) }

    private func sendCommand(_ command: RemoteCommand) {
        guard phase == .paired else { return }
        sender.send(.command(command))
    }

    /// Each Watch movement is equivalent to one `.next`.
    func startListeningToWatch() {
        movementSource.onMovementReceived = { [weak self] in
            MainActor.assumeIsolated { self?.next() }
        }
    }

    func stopListeningToWatch() {
        movementSource.onMovementReceived = nil
    }
}
