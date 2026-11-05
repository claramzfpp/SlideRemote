//
//  CommandReceiving.swift
//  SlideRemote
//
//  Contrato de transporte do lado iPad: recebe comandos e informa a conexão.
//

import Foundation

protocol CommandReceiving: AnyObject {
    /// Sempre chamados na main thread.
    var onCommand: (@MainActor (RemoteCommand) -> Void)? { get set }
    var onConnectionChange: (@MainActor (Bool) -> Void)? { get set }

    func start()
    func stop()
}
