//
//  InvitationPolicy.swift
//  SlideRemote
//

import Foundation

enum InvitationDecision: Equatable, Sendable {
    case askUser
    case reject
}

enum InvitationPolicy {
    /// Um iPhone por vez: enquanto houver um conectado ou aguardando aprovação, os outros são recusados sem incomodar o apresentador.
    static func decide(hasActivePeer: Bool) -> InvitationDecision {
        hasActivePeer ? .reject : .askUser
    }
}
