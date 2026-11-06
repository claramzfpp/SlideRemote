//
//  RemoteCommandSending.swift
//  SlideRemote
//
//  Contract for discovering iPads, connecting and exchanging messages, independent of the transport.
//

import Combine

/// iPad found on the network. `id` is stable while the iPad is visible.
struct DiscoveredPeer: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

@MainActor
protocol RemoteCommandSending: AnyObject {
    var discoveredPeers: [DiscoveredPeer] { get }
    var discoveredPeersPublisher: AnyPublisher<[DiscoveredPeer], Never> { get }

    var isConnected: Bool { get }
    /// Emits `true` on connect and `false` on each drop or incomplete invitation.
    var isConnectedPublisher: AnyPublisher<Bool, Never> { get }

    /// Called on the main thread for each message received from the iPad.
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
