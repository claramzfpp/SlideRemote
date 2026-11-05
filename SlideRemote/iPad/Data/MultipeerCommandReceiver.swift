//
//  MultipeerCommandReceiver.swift
//  SlideRemote
//
//  Roda no iPad: anuncia o serviço via MultipeerConnectivity e aceita o iPhone.
//

import MultipeerConnectivity // comunicação peer-to-peer local, sem servidor ou internet
/*
 um framework para comunicação direta entre dispositivos próximos, sem servidor e sem backend
 funciona entre iPhone, iPad e Mac

 ele escolhe sozinho o meio de transporte disponível:
 - wi-Fi na mesma rede (infraestrutura)
 - peer-to-peer Wi-Fi (AWDL, parecido com o AirDrop), sem precisar de roteador
 - bluetooth

 ele decide e troca de um para outro conforme a disponibilidade
 */

final class MultipeerCommandReceiver: NSObject, CommandReceiving {
    var onCommand: (@MainActor (RemoteCommand) -> Void)?
    var onConnectionChange: (@MainActor (Bool) -> Void)?

    private let serviceType = RemoteService.type
    private let peerID = MCPeerID(displayName: UIDevice.current.name) // identidade do ipad na rede (definido como o nome do dispositivo)
    private let mcSession: MCSession  // sessão de comunicação
    private let mcAdvertiser: MCNearbyServiceAdvertiser // anunciador do serviço

    override init() {
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required) // tráfego criptografado
        mcAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType) // o iphone procura exatamente esse identificador
        super.init()
        mcSession.delegate = self
        mcAdvertiser.delegate = self
    }

    func start() {
        mcAdvertiser.startAdvertisingPeer()
        print("iPad está anunciando o serviço \(serviceType) como: \(peerID.displayName)")
    }

    func stop() {
        mcAdvertiser.stopAdvertisingPeer()
        mcSession.disconnect()
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerCommandReceiver: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Recebeu um convite de \(peerID.displayName)")
        // TODO: pareamento seguro
        invitationHandler(true, mcSession)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Erro ao anunciar: \(error.localizedDescription)")
    }
}

// MARK: - MCSessionDelegate

extension MultipeerCommandReceiver: MCSessionDelegate {
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let command = RemoteCommand(data: data) else {
            print("Comando desconhecido")
            return
        }
        print("Comando recebido: \(command.rawValue)")

        DispatchQueue.main.async {
            self.onCommand?(command)
        }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("Estado da conexão com \(peerID.displayName): \(state.rawValue)")
        DispatchQueue.main.async {
            self.onConnectionChange?(!session.connectedPeers.isEmpty)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
