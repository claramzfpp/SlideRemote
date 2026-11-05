//
//  PairingSessionTests.swift
//  SlideRemoteTests
//

import Testing
@testable import SlideRemote

struct PairingSessionTests {
    private let correct = PairingCode("111111")!
    private let wrong = PairingCode("222222")!

    private func makeSession(maxAttempts: Int = 3) -> PairingSession {
        PairingSession(code: correct, maxAttempts: maxAttempts)
    }

    @Test func startsUnauthenticatedAndUnlocked() {
        let session = makeSession()
        #expect(!session.isAuthenticated)
        #expect(!session.isLocked)
    }

    @Test func correctCodeAuthenticates() {
        var session = makeSession()
        #expect(session.submit(correct) == .accepted)
        #expect(session.isAuthenticated)
    }

    @Test func wrongCodeReportsRemainingAttempts() {
        var session = makeSession()
        #expect(session.submit(wrong) == .rejected(attemptsLeft: 2))
        #expect(session.submit(wrong) == .rejected(attemptsLeft: 1))
        #expect(!session.isAuthenticated)
    }

    @Test func lastWrongAttemptLocksTheSession() {
        var session = makeSession()
        _ = session.submit(wrong)
        _ = session.submit(wrong)
        #expect(session.submit(wrong) == .locked)
        #expect(session.isLocked)
    }

    @Test func lockedSessionRejectsEvenTheCorrectCode() {
        var session = makeSession()
        for _ in 0..<3 { _ = session.submit(wrong) }
        #expect(session.submit(correct) == .locked)
        #expect(!session.isAuthenticated)
    }

    @Test func correctCodeAfterFailuresStillAuthenticatesWhileUnlocked() {
        var session = makeSession()
        _ = session.submit(wrong)
        #expect(session.submit(correct) == .accepted)
        #expect(session.isAuthenticated)
    }

    @Test func submittingAgainAfterAuthenticationStaysAccepted() {
        var session = makeSession()
        _ = session.submit(correct)
        #expect(session.submit(wrong) == .accepted)
        #expect(session.isAuthenticated)
    }

    @Test func singleAttemptSessionLocksOnFirstMistake() {
        var session = makeSession(maxAttempts: 1)
        #expect(session.submit(wrong) == .locked)
    }
}
