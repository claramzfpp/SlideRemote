//
//  PresentationReceiver.swift
//  SlideRemote
//
//  Roda no iPad: anuncia o serviço, aceita o iPhone e controla o slide atual.
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
import PDFKit
import Combine

class PresentationReceiver: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, ObservableObject {
    private let serviceType = "number-sync"
    private let peerID = MCPeerID(displayName: UIDevice.current.name) // identidade do ipad na rede (definido como o nome do dispositivo)
    private let mcSession: MCSession  // sessão de comunicação
    private let mcAdvertiser: MCNearbyServiceAdvertiser // anunciador do serviço

    @Published private(set) var document: PDFDocument?
    @Published private(set) var presentation: Presentation?
    @Published private(set) var isConnected = false
    @Published private(set) var loadError: String?

    override init() {
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required) //to definindo que o tráfego de info é criptografado
        mcAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType) // crio o trafego com o meu service type, o iphone vai procurar exatamente esse identificador
        super.init()
        mcSession.delegate = self
        mcAdvertiser.delegate = self
        mcAdvertiser.startAdvertisingPeer()
        print("iPad está anunciando o serviço \(serviceType) como: \(peerID.displayName)")
    }

    // MARK: - PDF

    /// Carrega o PDF escolhido pelo usuário. Deve rodar na main thread.
    func loadPDF(from url: URL) {
        // O arquivo vem do seletor de arquivos, fora do sandbox do app.
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            // Lê tudo para a memória enquanto o acesso está aberto.
            let data = try Data(contentsOf: url)
            guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
                loadError = "Não foi possível abrir esse PDF."
                return
            }
            document = pdf
            presentation = Presentation(pageCount: pdf.pageCount)
            loadError = nil
        } catch {
            loadError = "Erro ao ler o arquivo: \(error.localizedDescription)"
        }
    }

    func closePresentation() {
        document = nil
        presentation = nil
    }

    // MARK: - MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Recebeu um convite de \(peerID.displayName)")
        invitationHandler(true, mcSession)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Erro ao anunciar: \(error.localizedDescription)")
    }

    // MARK: - MCSessionDelegate

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let command = RemoteCommand(data: data) else {
            print("Comando desconhecido")
            return
        }
        print("Comando recebido: \(command.rawValue)")

        DispatchQueue.main.async {
            // Sem PDF carregado não há o que avançar.
            self.presentation?.apply(command)
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
