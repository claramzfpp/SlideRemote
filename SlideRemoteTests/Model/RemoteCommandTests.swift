//
//  RemoteCommandTests.swift
//  SlideRemoteTests
//

import Testing
import Foundation
@testable import SlideRemote

struct RemoteCommandTests {
    @Test func roundTripsThroughData() {
        for command in [RemoteCommand.next, .previous] {
            #expect(RemoteCommand(data: command.data) == command)
        }
    }

    @Test func rejectsUnknownPayload() {
        #expect(RemoteCommand(data: Data("jump".utf8)) == nil)
    }

    @Test func rejectsEmptyPayload() {
        #expect(RemoteCommand(data: Data()) == nil)
    }

    @Test func rejectsInvalidUTF8() {
        #expect(RemoteCommand(data: Data([0xFF, 0xFE])) == nil)
    }
}
