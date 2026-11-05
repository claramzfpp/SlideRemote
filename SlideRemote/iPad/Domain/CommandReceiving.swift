//
//  CommandReceiving.swift
//  SlideRemote
//
//  Contrato de transporte do lado iPad: convites, mensagens e conexão do iPhone.
//

import Foundation

protocol CommandReceiving: AnyObject {
    /// Sempre chamados na main thread.
    var onMessage: (@MainActor (RemoteMessage) -> Void)? { get set }
    var onConnectionChange: (@MainActor (Bool) -> Void)? { get set }
    /// Só é chamado para convites que precisam de resposta do usuário, com o nome do peer.
    var onInvitation: (@MainActor (String) -> Void)? { get set }

    func start()
    func stop()
    /// Responde ao convite aguardando decisão. Sem convite pendente, não faz nada.
    func respondToInvitation(accept: Bool)
    func send(_ message: RemoteMessage)
    func disconnectPeer()
}
