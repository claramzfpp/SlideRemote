//
//  RemoteCommandSending.swift
//  SlideRemote
//
//  Contrato para descobrir iPads, conectar e trocar mensagens, independente do transporte.
//

import Combine

/// iPad encontrado na rede. `id` é estável enquanto o iPad estiver visível.
struct DiscoveredPeer: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

@MainActor
protocol RemoteCommandSending: AnyObject {
    var discoveredPeers: [DiscoveredPeer] { get }
    var discoveredPeersPublisher: AnyPublisher<[DiscoveredPeer], Never> { get }

    var isConnected: Bool { get }
    /// Emite `true` ao conectar e `false` a cada queda ou convite não completado.
    var isConnectedPublisher: AnyPublisher<Bool, Never> { get }

    /// Chamado na main thread para cada mensagem recebida do iPad.
    var onMessage: ((RemoteMessage) -> Void)? { get set }

    func connect(to peer: DiscoveredPeer)
    func disconnect()
    func send(_ message: RemoteMessage)
}

@MainActor
protocol MovementSource: AnyObject {
    var onMovementReceived: (() -> Void)? { get set }
}

extension WatchConnectivityManager: MovementSource {}
