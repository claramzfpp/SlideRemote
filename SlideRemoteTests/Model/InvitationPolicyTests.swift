//
//  InvitationPolicyTests.swift
//  SlideRemoteTests
//

import Testing
@testable import SlideRemote

struct InvitationPolicyTests {
    @Test func asksTheUserWhenNobodyIsConnected() {
        #expect(InvitationPolicy.decide(hasActivePeer: false) == .askUser)
    }

    @Test func rejectsWhileAnotherPeerIsActive() {
        #expect(InvitationPolicy.decide(hasActivePeer: true) == .reject)
    }
}
