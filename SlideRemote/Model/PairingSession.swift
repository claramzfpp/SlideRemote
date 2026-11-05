//
//  PairingSession.swift
//  SlideRemote
//

import Foundation

enum PairingResult: Equatable, Sendable {
    case accepted
    case rejected(attemptsLeft: Int)
    case locked
}

/// Estado do pareamento de um iPhone com o iPad. Depois de `maxAttempts` erros fica travado
/// para sempre: um novo código só existe numa nova sessão.
struct PairingSession: Sendable {
    private let code: PairingCode
    private let maxAttempts: Int
    private var failedAttempts = 0
    private(set) var isAuthenticated = false

    init(code: PairingCode, maxAttempts: Int = 3) {
        self.code = code
        self.maxAttempts = max(maxAttempts, 1)
    }

    var isLocked: Bool { !isAuthenticated && failedAttempts >= maxAttempts }

    mutating func submit(_ attempt: PairingCode) -> PairingResult {
        if isAuthenticated { return .accepted }
        if isLocked { return .locked }

        if code.matches(attempt) {
            isAuthenticated = true
            return .accepted
        }

        failedAttempts += 1
        return isLocked ? .locked : .rejected(attemptsLeft: maxAttempts - failedAttempts)
    }
}
