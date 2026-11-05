//
//  RemoteMessageTests.swift
//  SlideRemoteTests
//

import Testing
import Foundation
@testable import SlideRemote

struct RemoteMessageTests {
    private let code = PairingCode("123456")!

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
            .pairingResult(.locked)
        ]
        for message in messages {
            #expect(RemoteMessage(data: message.data) == message)
        }
    }

    @Test(arguments: [
        "", "jump", "pair:", "pair:12345", "pair:abcdef", "pair:1234567",
        "pairing:", "pairing:unknown", "pairing:rejected", "pairing:rejected:-1",
        "pairing:rejected:x", "pairing:rejected:99999999999999999999", "NEXT", "next "
    ])
    func rejectsMalformedPayloads(_ raw: String) {
        #expect(RemoteMessage(data: Data(raw.utf8)) == nil)
    }

    @Test func rejectsInvalidUTF8() {
        #expect(RemoteMessage(data: Data([0xFF, 0xFE])) == nil)
    }
}
