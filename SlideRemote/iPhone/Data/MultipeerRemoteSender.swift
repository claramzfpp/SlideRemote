//
//  MultipeerRemoteSender.swift
//  SlideRemote
//
//  Procura o iPad via Multipeer e envia os comandos. Todo o estado mutável
//  é acessado só na main thread; callbacks do MPC fazem hop para ela.
//

import MultipeerConnectivity
import Combine

@MainActor
final class MultipeerRemoteSender: NSObject, RemoteCommandSending {
    private let isConnectedSubject = CurrentValueSubject<Bool, Never>(false)
    var isConnected: Bool { isConnectedSubject.value }
    var isConnectedPublisher: AnyPublisher<Bool, Never> { isConnectedSubject.eraseToAnyPublisher() }

    private let peerID: MCPeerID
    nonisolated private let session: MCSession
    private let browser: MCNearbyServiceBrowser
    private var connectedPeer: MCPeerID?

    override init() {
        peerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: RemoteService.type)
        super.init()
        session.delegate = self
        browser.delegate = self
        browser.startBrowsingForPeers()
        print("iPhone está navegando pelo serviço \(RemoteService.type)")
    }

    func send(_ command: RemoteCommand) {
        guard let peer = connectedPeer else {
            print("Nenhum iPad conectado.")
            return
        }
        do {
            try session.send(command.data, toPeers: [peer], with: .reliable)
            print("Comando enviado: \(command.rawValue)")
        } catch {
            print("Erro ao enviar o comando: \(error.localizedDescription)")
        }
    }

    private func update(peer: MCPeerID, state: MCSessionState) {
        switch state {
        case .connected:
            print("Conectado a: \(peer.displayName)")
            connectedPeer = peer
        case .notConnected:
            print("Desconectado de: \(peer.displayName)")
            connectedPeer = nil
        case .connecting:
            print("Conectando a: \(peer.displayName)")
        @unknown default:
            print("Estado desconhecido: \(state)")
        }
        isConnectedSubject.send(connectedPeer != nil)
    }
}

extension MultipeerRemoteSender: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("Peer encontrado: \(peerID.displayName)")
        // TODO: pareamento seguro
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Peer perdido: \(peerID.displayName)")
    }
}

extension MultipeerRemoteSender: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            self?.update(peer: peerID, state: state)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
