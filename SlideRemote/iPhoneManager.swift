//
//  iPhoneManager.swift
//  RotateWritsDetection
//
//  Created by Clara Muniz on 19/09/25.
//

import MultipeerConnectivity
import Combine

class iPhoneManager: NSObject, MCSessionDelegate, MCNearbyServiceBrowserDelegate, ObservableObject {
    @Published private(set) var isConnected = false

    private let serviceType = "number-sync"
    private var peerID: MCPeerID!
    private var mcBrowser: MCNearbyServiceBrowser!
    private var mcSession: MCSession!
    private var connectedPeer: MCPeerID?

    override init() {
        super.init()
        self.peerID = MCPeerID(displayName: UIDevice.current.name)
        self.mcSession = MCSession(peer: self.peerID, securityIdentity: nil, encryptionPreference: .required)
        self.mcSession.delegate = self
        self.mcBrowser = MCNearbyServiceBrowser(peer: self.peerID, serviceType: self.serviceType)
        self.mcBrowser.delegate = self
        self.mcBrowser.startBrowsingForPeers()
        print("iPhone está navegando pelo serviço \(serviceType)")
    }

    // MARK: - MCNearbyServiceBrowserDelegate

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("Peer encontrado: \(peerID.displayName)")
        browser.invitePeer(peerID, to: self.mcSession, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Peer perdido: \(peerID.displayName)")
    }

    // MARK: - MCSessionDelegate

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            print("Conectado a: \(peerID.displayName)")
            self.connectedPeer = peerID
        case .notConnected:
            print("Desconectado de: \(peerID.displayName)")
            self.connectedPeer = nil
        case .connecting:
            print("Conectando a: \(peerID.displayName)")
        @unknown default:
            print("Estado desconhecido: \(state)")
        }

        DispatchQueue.main.async {
            self.isConnected = self.connectedPeer != nil
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // Método para avançar o slide
    func sendNextSlideCommand() {
        sendCommand(command: "nextSlide")
    }

    // Método para voltar o slide
    func sendPreviousSlideCommand() {
        sendCommand(command: "previousSlide")
    }

    // Método utilitário genérico
    private func sendCommand(command: String) {
        guard let peer = self.connectedPeer else {
            print("Nenhum iPad conectado.")
            return
        }
        do {
            let data = command.data(using: .utf8)!
            try self.mcSession.send(data, toPeers: [peer], with: .reliable)
            print("Comando enviado: \(command)")
        } catch {
            print("Erro ao enviar o comando: \(error.localizedDescription)")
        }
    }
}
