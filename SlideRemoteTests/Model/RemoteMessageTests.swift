//
//  RemoteMessageTests.swift
//  SlideRemoteTests
//

import Testing
import Foundation
@testable import SlideRemote

struct RemoteMessageTests {
    private let code = PairingCode("123456")!
    private let token = HexToken("0123456789abcdef0123456789abcdef")!
    private let proof = ResumeProof(String(repeating: "ab", count: 32))!

    @Test func commandsKeepTheirOriginalWireFormat() {
        #expect(RemoteMessage.command(.next).data == Data("next".utf8))
        #expect(RemoteMessage.command(.previous).data == Data("previous".utf8))
    }

    @Test func roundTripsEveryMessage() {
        let messages: [RemoteMessage] = [
            .command(.next),
            .command(.previous),
            .pair(code),
            .pairingResult(.accepted),
            .pairingResult(.rejected(attemptsLeft: 2)),
            .pairingResult(.rejected(attemptsLeft: 0)),
            .pairingResult(.locked),
            .credential(token),
            .resumeRequest,
            .resumeChallenge(token),
            .resumeProof(proof),
            .resumeRejected
        ]
        for message in messages {
            #expect(RemoteMessage(data: message.data) == message)
        }
    }

    @Test(arguments: [
        "", "jump", "pair:", "pair:12345", "pair:abcdef", "pair:1234567",
        "pairing:", "pairing:unknown", "pairing:rejected", "pairing:rejected:-1",
        "pairing:rejected:x", "pairing:rejected:99999999999999999999", "NEXT", "next ",
        "credential:", "credential:abc", "credential:0123456789ABCDEF0123456789ABCDEF",
        "challenge:", "challenge:0123456789abcdef0123456789abcdeg",
        "proof:", "proof:abc", "resume:", "resume:accepted", "Resume"
    ])
    func rejectsMalformedPayloads(_ raw: String) {
        #expect(RemoteMessage(data: Data(raw.utf8)) == nil)
    }

    @Test func resumeMessagesHaveStableWireFormats() {
        #expect(RemoteMessage.resumeRequest.data == Data("resume".utf8))
        #expect(RemoteMessage.resumeRejected.data == Data("resume:rejected".utf8))
        #expect(RemoteMessage.credential(token).data == Data("credential:0123456789abcdef0123456789abcdef".utf8))
        #expect(RemoteMessage.resumeChallenge(token).data == Data("challenge:0123456789abcdef0123456789abcdef".utf8))
    }

    @Test func rejectsInvalidUTF8() {
        #expect(RemoteMessage(data: Data([0xFF, 0xFE])) == nil)
    }
}
