//
//  CommandThrottleTests.swift
//  SlideRemoteTests
//

import Testing
@testable import SlideRemote

struct CommandThrottleTests {
    private let start = ContinuousClock.now

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .milliseconds(milliseconds))
    }

    @Test func allowsUpToTheMaximumWithinTheWindow() {
        var throttle = CommandThrottle(maxCommands: 3, window: .seconds(1))
        #expect(throttle.allow(at: at(0)))
        #expect(throttle.allow(at: at(0)))
        #expect(throttle.allow(at: at(0)))
        #expect(!throttle.allow(at: at(0)))
    }

    @Test func releasesTheBlockOnceTheWindowHasPassed() {
        var throttle = CommandThrottle(maxCommands: 3, window: .seconds(1))
        for _ in 0..<3 { _ = throttle.allow(at: at(0)) }
        #expect(!throttle.allow(at: at(999)))
        #expect(throttle.allow(at: at(1_000)))
    }

    @Test func deniedAttemptsDoNotExtendTheBlock() {
        var throttle = CommandThrottle(maxCommands: 1, window: .seconds(1))
        #expect(throttle.allow(at: at(0)))
        #expect(!throttle.allow(at: at(500)))
        #expect(throttle.allow(at: at(1_000)))
    }

    @Test func commandsSpreadOverTimeAreNeverBlocked() {
        var throttle = CommandThrottle(maxCommands: 2, window: .seconds(1))
        for step in 0..<10 {
            #expect(throttle.allow(at: at(step * 600)))
        }
    }

    @Test func aMaximumBelowOneStillAllowsOneCommand() {
        var throttle = CommandThrottle(maxCommands: 0, window: .seconds(1))
        #expect(throttle.allow(at: at(0)))
        #expect(!throttle.allow(at: at(0)))
    }
}
