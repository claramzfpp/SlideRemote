//
//  CommandThrottle.swift
//  SlideRemote
//

import Foundation

/// Sliding window: at most `maxCommands` commands within `window`.
/// Denied attempts don't count, so a flood doesn't extend the block beyond the window.
struct CommandThrottle: Sendable {
    private let maxCommands: Int
    private let window: Duration
    private var accepted: [ContinuousClock.Instant] = []

    init(maxCommands: Int, window: Duration) {
        self.maxCommands = max(maxCommands, 1)
        self.window = window
    }

    mutating func allow(at now: ContinuousClock.Instant) -> Bool {
        accepted.removeAll { now - $0 >= window }
        guard accepted.count < maxCommands else { return false }
        accepted.append(now)
        return true
    }
}
