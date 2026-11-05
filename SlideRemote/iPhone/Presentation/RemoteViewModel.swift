//
//  RemoteViewModel.swift
//  SlideRemote
//
//  Conduz o pareamento com o iPad e, depois dele, liga a tela aos comandos e aos movimentos do Watch.
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
    /// Aviso mostrado na busca depois de uma falha (bloqueio, queda, convite recusado).
    @Published private(set) var notice: String?
    /// Erro de formato do código digitado.
    @Published private(set) var codeError: String?

    private let sender: RemoteCommandSending
    private let movementSource: MovementSource
    private var cancellables = Set<AnyCancellable>()

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

    // MARK: - Pareamento

    func select(_ peer: DiscoveredPeer) {
        guard phase == .searching else { return }
        notice = nil
        codeError = nil
        phase = .connecting(peerName: peer.name)
        sender.connect(to: peer)
    }

    func cancelConnection() {
        guard phase != .searching else { return }
        sender.disconnect()
        phase = .searching
    }

    func submitCode(_ input: String) {
        guard case .enteringCode = phase else { return }
        guard let code = PairingCode(input) else {
            codeError = "Digite os 6 dígitos"
            return
        }
        codeError = nil
        phase = .verifying
        sender.send(.pair(code))
    }

    private func connectionChanged(isConnected: Bool) {
        switch (phase, isConnected) {
        case (.connecting, true):
            phase = .enteringCode(attemptsLeft: nil)
        case (.connecting, false):
            fallBackToSearching(notice: "O iPad recusou ou não respondeu")
        case (.searching, _), (_, true):
            break
        case (_, false):
            fallBackToSearching(notice: "Conexão perdida")
        }
    }

    private func handle(_ message: RemoteMessage) {
        guard case .pairingResult(let result) = message, phase == .verifying else { return }
        switch result {
        case .accepted:
            phase = .paired
        case .rejected(let attemptsLeft):
            phase = .enteringCode(attemptsLeft: attemptsLeft)
        case .locked:
            sender.disconnect()
            fallBackToSearching(notice: "Pareamento bloqueado. Peça um novo código no iPad.")
        }
    }

    private func fallBackToSearching(notice: String) {
        self.notice = notice
        codeError = nil
        phase = .searching
    }

    // MARK: - Controle

    func next() { sendCommand(.next) }
    func previous() { sendCommand(.previous) }

    private func sendCommand(_ command: RemoteCommand) {
        guard phase == .paired else { return }
        sender.send(.command(command))
    }

    /// Cada movimento do Watch equivale a um `.next`.
    func startListeningToWatch() {
        movementSource.onMovementReceived = { [weak self] in
            MainActor.assumeIsolated { self?.next() }
        }
    }

    func stopListeningToWatch() {
        movementSource.onMovementReceived = nil
    }
}
