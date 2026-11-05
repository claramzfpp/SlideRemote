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
    var onMessage: (@MainActor (RemoteMessage) -> Void)?
    var onConnectionChange: (@MainActor (Bool) -> Void)?
    var onInvitation: (@MainActor (String) -> Void)?

    private let serviceType = RemoteService.type
    private let peerID = MCPeerID(displayName: UIDevice.current.name) // identidade do ipad na rede (definido como o nome do dispositivo)
    private let mcSession: MCSession  // sessão de comunicação
    private let mcAdvertiser: MCNearbyServiceAdvertiser // anunciador do serviço

    // Estado de convites: só é lido e escrito na main thread.
    private var pendingInvitation: (peer: MCPeerID, handler: (Bool, MCSession?) -> Void)?
    private var approvedPeer: MCPeerID? // aprovado, mas ainda conectando

    override init() {
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required) // tráfego criptografado
        mcAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType) // o iphone procura exatamente esse identificador
        super.init()
        mcSession.delegate = self
        mcAdvertiser.delegate = self
    }

    func start() {
        mcAdvertiser.startAdvertisingPeer()
        AppLog.connectivity.info("Anunciando o serviço \(self.serviceType, privacy: .public) como \(self.peerID.displayName, privacy: .private)")
    }

    func stop() {
        mcAdvertiser.stopAdvertisingPeer()
        mcSession.disconnect()
        DispatchQueue.main.async {
            self.pendingInvitation?.handler(false, nil)
            self.pendingInvitation = nil
            self.approvedPeer = nil
        }
    }

    func respondToInvitation(accept: Bool) {
        let respond = { [self] in
            guard let pending = pendingInvitation else { return }
            pendingInvitation = nil
            if accept {
                approvedPeer = pending.peer
                pending.handler(true, mcSession)
            } else {
                pending.handler(false, nil)
            }
        }
        if Thread.isMainThread { respond() } else { DispatchQueue.main.async(execute: respond) }
    }

    func send(_ message: RemoteMessage) {
        let peers = mcSession.connectedPeers
        guard !peers.isEmpty else { return }
        do {
            try mcSession.send(message.data, toPeers: peers, with: .reliable)
        } catch {
            AppLog.connectivity.error("Erro ao enviar mensagem: \(error.localizedDescription, privacy: .public)")
        }
    }

    func disconnectPeer() {
        mcSession.disconnect()
        // Libera também quem foi aprovado mas nunca completou a conexão; senão a vaga ficaria presa.
        DispatchQueue.main.async { self.approvedPeer = nil }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerCommandReceiver: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        AppLog.connectivity.info("Convite recebido de \(peerID.displayName, privacy: .private)")
        DispatchQueue.main.async {
            let hasActivePeer = self.pendingInvitation != nil
                || self.approvedPeer != nil
                || !self.mcSession.connectedPeers.isEmpty
            switch InvitationPolicy.decide(hasActivePeer: hasActivePeer) {
            case .reject:
                invitationHandler(false, nil)
            case .askUser:
                self.pendingInvitation = (peerID, invitationHandler)
                self.onInvitation?(peerID.displayName)
            }
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        AppLog.connectivity.error("Erro ao anunciar: \(error.localizedDescription, privacy: .public)")
    }
}

// MARK: - MCSessionDelegate

extension MultipeerCommandReceiver: MCSessionDelegate {
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Conteúdo nunca é logado: pode ser o código de pareamento.
        guard let message = RemoteMessage(data: data) else { return }

        DispatchQueue.main.async {
            self.onMessage?(message)
        }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        AppLog.connectivity.info("Estado da conexão com \(peerID.displayName, privacy: .private): \(state.rawValue, privacy: .public)")
        DispatchQueue.main.async {
            // "Conectando" ainda não é queda: avisar agora apagaria o código recém-criado.
            guard state != .connecting else { return }
            if self.approvedPeer == peerID { self.approvedPeer = nil }
            self.onConnectionChange?(!session.connectedPeers.isEmpty)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
