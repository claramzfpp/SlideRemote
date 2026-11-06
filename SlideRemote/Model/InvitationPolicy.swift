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
    /// One iPhone at a time: while one is connected or awaiting approval, the others are declined without bothering the presenter.
    static func decide(hasActivePeer: Bool) -> InvitationDecision {
        hasActivePeer ? .reject : .askUser
    }
}
