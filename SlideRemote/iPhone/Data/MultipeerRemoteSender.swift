//
//  MultipeerRemoteSender.swift
//  SlideRemote
//
//  Procura iPads via Multipeer, convida só o que o usuário escolher e troca mensagens.
//  Todo o estado mutável é acessado só na main thread; callbacks do MPC fazem hop para ela.
//  Nunca registra o conteúdo das mensagens (inclui o código de pareamento).
//

import MultipeerConnectivity
import Combine

@MainActor
final class MultipeerRemoteSender: NSObject, RemoteCommandSending {
    /// O apresentador precisa aprovar o convite no iPad, então o prazo é generoso.
    private static let invitationTimeout: TimeInterval = 30

    private let peersSubject = CurrentValueSubject<[DiscoveredPeer], Never>([])
    var discoveredPeers: [DiscoveredPeer] { peersSubject.value }
    var discoveredPeersPublisher: AnyPublisher<[DiscoveredPeer], Never> { peersSubject.eraseToAnyPublisher() }

    private let isConnectedSubject = CurrentValueSubject<Bool, Never>(false)
    var isConnected: Bool { isConnectedSubject.value }
    var isConnectedPublisher: AnyPublisher<Bool, Never> { isConnectedSubject.eraseToAnyPublisher() }

    var onMessage: ((RemoteMessage) -> Void)?

    private let peerID: MCPeerID
    nonisolated private let session: MCSession
    private let browser: MCNearbyServiceBrowser
    /// Mapa id estável -> MCPeerID dos iPads visíveis.
    private var knownPeers: [(peer: DiscoveredPeer, mcPeer: MCPeerID)] = []
    /// iPad convidado ou conectado; eventos de outros peers são ignorados.
    private var targetPeer: MCPeerID?
    private var connectedPeer: MCPeerID?

    override init() {
        peerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: RemoteService.type)
        super.init()
        session.delegate = self
        browser.delegate = self
        browser.startBrowsingForPeers()
    }

    func connect(to peer: DiscoveredPeer) {
        guard let mcPeer = knownPeers.first(where: { $0.peer.id == peer.id })?.mcPeer else { return }
        targetPeer = mcPeer
        browser.invitePeer(mcPeer, to: session, withContext: nil, timeout: Self.invitationTimeout)
    }

    func disconnect() {
        targetPeer = nil
        connectedPeer = nil
        session.disconnect()
    }

    func send(_ message: RemoteMessage) {
        guard let peer = connectedPeer else { return }
        do {
            try session.send(message.data, toPeers: [peer], with: .reliable)
        } catch {
            print("Erro ao enviar a mensagem: \(error.localizedDescription)")
        }
    }

    private func update(peer: MCPeerID, state: MCSessionState) {
        guard peer == targetPeer else { return }
        switch state {
        case .connected:
            connectedPeer = peer
            isConnectedSubject.send(true)
        case .notConnected:
            targetPeer = nil
            connectedPeer = nil
            isConnectedSubject.send(false)
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    private func found(_ mcPeer: MCPeerID) {
        guard !knownPeers.contains(where: { $0.mcPeer == mcPeer }) else { return }
        let peer = DiscoveredPeer(id: UUID().uuidString, name: mcPeer.displayName)
        knownPeers.append((peer, mcPeer))
        peersSubject.send(knownPeers.map(\.peer))
    }

    private func lost(_ mcPeer: MCPeerID) {
        knownPeers.removeAll { $0.mcPeer == mcPeer }
        peersSubject.send(knownPeers.map(\.peer))
    }

    private func received(_ message: RemoteMessage, from peer: MCPeerID) {
        guard peer == connectedPeer else { return }
        onMessage?(message)
    }
}

extension MultipeerRemoteSender: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor [weak self] in self?.found(peerID) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in self?.lost(peerID) }
    }
}

extension MultipeerRemoteSender: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            self?.update(peer: peerID, state: state)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = RemoteMessage(data: data) else { return }
        Task { @MainActor [weak self] in
            self?.received(message, from: peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
