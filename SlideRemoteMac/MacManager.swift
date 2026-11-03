//
//  MacManager.swift
//  RotateWritsDetection
//
//  Created by Clara Muniz on 19/09/25.
//

import MultipeerConnectivity
import Combine

// ObservableObject para publicar mudanças
class MacManager: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, ObservableObject {
    private let serviceType = "number-sync"
    private var peerID: MCPeerID!
    private var mcAdvertiser: MCNearbyServiceAdvertiser!
    private var mcSession: MCSession!

    // Publica o número atual para que a UI possa reagir a mudanças
    @Published var currentNumber = 0

    override init() {
        super.init()
        self.peerID = MCPeerID(displayName: Host.current().name!)
        self.mcSession = MCSession(peer: self.peerID, securityIdentity: nil, encryptionPreference: .required)
        self.mcSession.delegate = self
        self.mcAdvertiser = MCNearbyServiceAdvertiser(
            peer: self.peerID,
            discoveryInfo: nil,
            serviceType: self.serviceType
        )
        self.mcAdvertiser.delegate = self
        self.mcAdvertiser.startAdvertisingPeer()
        print("Mac está anunciando o serviço \(serviceType) como: \(self.peerID.displayName)")
    }

    // MARK: - MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Recebeu um convite de \(peerID.displayName)")
        invitationHandler(true, self.mcSession)
    }

    // MARK: - MCSessionDelegate

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let receivedCommand = String(data: data, encoding: .utf8) {
            print("Comando recebido do iPhone: \(receivedCommand)")

            DispatchQueue.main.async {
                switch receivedCommand {
                case "nextSlide":
                    self.currentNumber += 1
                    self.executeAppleScript("tell application \"Keynote\" to show next")
                case "previousSlide":
                    self.currentNumber -= 1
                    self.executeAppleScript("tell application \"Keynote\" to show previous")
                default:
                    print("Comando desconhecido: \(receivedCommand)")
                }
            }
        }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        // Implemente a lógica para exibir o estado da conexão na UI (opcional)
        print("Estado da conexão com \(peerID.displayName) mudou para \(state)")
    }

    // Métodos delegados restantes...
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MacManager {
    func executeAppleScript(_ script: String) {
        guard let appleScript = NSAppleScript(source: script) else {
            print("Erro ao criar o script AppleScript")
            return
        }

        var errorDict: NSDictionary?
        appleScript.executeAndReturnError(&errorDict)

        if let error = errorDict {
            print("Erro ao executar AppleScript: \(error)")
        }
    }
}
