//
//  CommandReceiving.swift
//  SlideRemote
//
//  Transport contract on the iPad side: invitations, messages and the iPhone connection.
//

import Foundation

protocol CommandReceiving: AnyObject {
    /// Always called on the main thread.
    var onMessage: (@MainActor (RemoteMessage) -> Void)? { get set }
    var onConnectionChange: (@MainActor (Bool) -> Void)? { get set }
    /// Only called for invitations that need a user response, with the peer's name.
    var onInvitation: (@MainActor (String) -> Void)? { get set }

    func start()
    func stop()
    /// Responds to the invitation awaiting a decision. With no pending invitation, does nothing.
    func respondToInvitation(accept: Bool)
    func send(_ message: RemoteMessage)
    func disconnectPeer()
}
