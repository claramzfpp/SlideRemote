//
//  RemoteViewModel.swift
//  SlideRemote
//
//  Liga a tela do iPhone ao envio de comandos e aos movimentos do Watch.
//

import Combine
import Foundation

@MainActor
final class RemoteViewModel: ObservableObject {
    @Published private(set) var isConnected: Bool

    private let sender: RemoteCommandSending
    private let movementSource: MovementSource
    private var cancellable: AnyCancellable?

    init(sender: RemoteCommandSending, movementSource: MovementSource) {
        self.sender = sender
        self.movementSource = movementSource
        self.isConnected = sender.isConnected
        cancellable = sender.isConnectedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isConnected = $0 }
    }

    func next() { sender.send(.next) }
    func previous() { sender.send(.previous) }

    /// Cada movimento do Watch equivale a um `.next`.
    func startListeningToWatch() {
        movementSource.onMovementReceived = { [weak self] in
            MainActor.assumeIsolated { self?.next() }
        }
    }

    func stopListeningToWatch() {
        movementSource.onMovementReceived = nil
    }
}
