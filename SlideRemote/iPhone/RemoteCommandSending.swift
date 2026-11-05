//
//  RemoteCommandSending.swift
//  SlideRemote
//
//  Contrato para enviar comandos ao iPad, independente do transporte.
//

import Combine

@MainActor
protocol RemoteCommandSending: AnyObject {
    var isConnected: Bool { get }
    var isConnectedPublisher: AnyPublisher<Bool, Never> { get }

    func send(_ command: RemoteCommand)
}

@MainActor
protocol MovementSource: AnyObject {
    var onMovementReceived: (() -> Void)? { get set }
}

extension WatchConnectivityManager: MovementSource {}
