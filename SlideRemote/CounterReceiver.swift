//
//  CounterReceiver.swift
//  SlideRemote
//
//  Roda no iPad: anuncia o serviço, aceita o iPhone e atualiza o contador.
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

import Combine

class CounterReceiver: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, ObservableObject {
    private let serviceType = "number-sync"
    private let peerID = MCPeerID(displayName: UIDevice.current.name) // identidade do ipad na rede (definido como o nome do dispositivo)
    private let mcSession: MCSession // sessão de comunicação
    private let mcAdvertiser: MCNearbyServiceAdvertiser // anunciador do serviço

    @Published private(set) var counter = 0
    @Published private(set) var isConnected = false

    override init() {
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required) //to definindo que o tráfego de info é criptografado
        mcAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType) // crio o trafego com o meu service type, o iphone vai procurar exatamente esse identificador
        super.init()
        mcSession.delegate = self
        mcAdvertiser.delegate = self
        mcAdvertiser.startAdvertisingPeer()
        print("iPad está anunciando o serviço \(serviceType) como: \(peerID.displayName)")
    }

    // MARK: - MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // estabelece a conexão entre os dois
        print("Recebeu um convite de \(peerID.displayName)")
        invitationHandler(true, mcSession)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Erro ao anunciar: \(error.localizedDescription)")
    }

    // MARK: - MCSessionDelegate

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let command = String(data: data, encoding: .utf8) else { return }
        print("Comando recebido: \(command)")

        DispatchQueue.main.async {
            switch command {
            case "nextSlide": self.counter += 1
            case "previousSlide": self.counter -= 1
            default: print("Comando desconhecido: \(command)")
            }
        }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("Estado da conexão com \(peerID.displayName): \(state.rawValue)")
        DispatchQueue.main.async {
            self.isConnected = !session.connectedPeers.isEmpty
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
