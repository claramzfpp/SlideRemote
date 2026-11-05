//
//  CommandThrottle.swift
//  SlideRemote
//

import Foundation

/// Janela deslizante: no máximo `maxCommands` comandos dentro de `window`.
/// Tentativas negadas não contam, então um flood não prolonga o bloqueio além da janela.
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
