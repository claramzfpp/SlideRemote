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
        let result1 = throttle.allow(at: at(0))
        #expect(result1)
        let result2 = throttle.allow(at: at(0))
        #expect(result2)
        let result3 = throttle.allow(at: at(0))
        #expect(result3)
        let result4 = throttle.allow(at: at(0))
        #expect(!result4)
    }

    @Test func releasesTheBlockOnceTheWindowHasPassed() {
        var throttle = CommandThrottle(maxCommands: 3, window: .seconds(1))
        for _ in 0..<3 { _ = throttle.allow(at: at(0)) }
        let result5 = throttle.allow(at: at(999))
        #expect(!result5)
        let result6 = throttle.allow(at: at(1_000))
        #expect(result6)
    }

    @Test func deniedAttemptsDoNotExtendTheBlock() {
        var throttle = CommandThrottle(maxCommands: 1, window: .seconds(1))
        let result7 = throttle.allow(at: at(0))
        #expect(result7)
        let result8 = throttle.allow(at: at(500))
        #expect(!result8)
        let result9 = throttle.allow(at: at(1_000))
        #expect(result9)
    }

    @Test func commandsSpreadOverTimeAreNeverBlocked() {
        var throttle = CommandThrottle(maxCommands: 2, window: .seconds(1))
        for step in 0..<10 {
            let result10 = throttle.allow(at: at(step * 600))
            #expect(result10)
        }
    }

    @Test func aMaximumBelowOneStillAllowsOneCommand() {
        var throttle = CommandThrottle(maxCommands: 0, window: .seconds(1))
        let result11 = throttle.allow(at: at(0))
        #expect(result11)
        let result12 = throttle.allow(at: at(0))
        #expect(!result12)
    }
}
