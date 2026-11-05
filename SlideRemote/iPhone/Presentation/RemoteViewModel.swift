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
    /// `true` enquanto retoma uma sessão anterior sem pedir o código.
    @Published private(set) var isResuming = false
    /// Erro de formato do código digitado.
    @Published private(set) var codeError: String?

    private let sender: RemoteCommandSending
    private let movementSource: MovementSource
    private var cancellables = Set<AnyCancellable>()
    /// Credenciais de reconexão por nome de iPad, só em memória: somem quando o app fecha.
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

    // MARK: - Pareamento

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
            codeError = "Digite os 6 dígitos"
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
                // Já pareado com este iPad nesta execução: tenta retomar sem pedir o código.
                isResuming = true
                phase = .verifying
                sender.send(.resumeRequest)
            } else {
                phase = .enteringCode(attemptsLeft: nil)
            }
        case (.connecting, false):
            fallBackToSearching(notice: "O iPad recusou ou não respondeu")
        case (.searching, _), (_, true):
            break
        case (_, false):
            fallBackToSearching(notice: "Conexão perdida")
        }
    }

    private func handle(_ message: RemoteMessage) {
        switch message {
        case .pairingResult(let result): handlePairingResult(result)
        case .credential(let token): store(token)
        case .resumeChallenge(let nonce): answer(nonce)
        case .resumeRejected: resumeWasRejected()
        case .command, .pair, .resumeRequest, .resumeProof:
            break // mensagens do iPhone para o iPad; ignoradas se vierem de volta
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
            fallBackToSearching(notice: "Pareamento bloqueado. Peça um novo código no iPad.")
        }
    }

    /// O iPad só emite a credencial depois de autenticar; fora disso é ignorada.
    private func store(_ token: HexToken) {
        guard phase == .verifying || phase == .paired, let name = currentPeerName else { return }
        credentials[name] = token
    }

    /// Responde ao desafio com uma prova (HMAC); a credencial em si nunca é enviada.
    private func answer(_ nonce: HexToken) {
        guard phase == .verifying, isResuming,
              let name = currentPeerName, let credential = credentials[name] else { return }
        sender.send(.resumeProof(ResumeProof.compute(credential: credential, nonce: nonce)))
    }

    private func resumeWasRejected() {
        guard phase == .verifying, isResuming else { return }
        forgetCredential()
        isResuming = false
        codeError = "A sessão anterior expirou. Digite o código mostrado no iPad."
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
