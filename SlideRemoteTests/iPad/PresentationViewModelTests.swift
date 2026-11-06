//
//  PresentationViewModelTests.swift
//  SlideRemoteTests
//

import Testing
import Foundation
import PDFKit
@testable import SlideRemote

@MainActor
final class FakeCommandReceiver: CommandReceiving {
    var onMessage: (@MainActor (RemoteMessage) -> Void)?
    var onConnectionChange: (@MainActor (Bool) -> Void)?
    var onInvitation: (@MainActor (String) -> Void)?

    private(set) var started = false
    private(set) var sent: [RemoteMessage] = []
    private(set) var disconnectCount = 0
    private(set) var responses: [Bool] = []

    // Mirrors the real receiver's rule: one peer at a time.
    private var hasPendingInvitation = false
    private var hasConnectedPeer = false
    private(set) var autoRejectedInvitations = 0

    func start() { started = true }
    func stop() { started = false }
    func send(_ message: RemoteMessage) { sent.append(message) }
    func disconnectPeer() { disconnectCount += 1 }

    func respondToInvitation(accept: Bool) {
        responses.append(accept)
        hasPendingInvitation = false
    }

    func simulateInvitation(from name: String) {
        let hasActive = hasPendingInvitation || hasConnectedPeer
        switch InvitationPolicy.decide(hasActivePeer: hasActive) {
        case .reject: autoRejectedInvitations += 1
        case .askUser:
            hasPendingInvitation = true
            onInvitation?(name)
        }
    }

    func simulateConnection(_ connected: Bool) {
        hasConnectedPeer = connected
        onConnectionChange?(connected)
    }

    func simulate(_ message: RemoteMessage) { onMessage?(message) }
}

private struct StubPDFLoader: PDFLoading {
    func load(from url: URL) throws(PDFLoadError) -> PDFDocument {
        let document = PDFDocument()
        for index in 0..<3 { document.insert(PDFPage(), at: index) }
        return document
    }
}

@MainActor
struct PresentationViewModelTests {
    private let receiver = FakeCommandReceiver()
    private let first = PairingCode("111111")!
    private let second = PairingCode("222222")!
    private let wrong = PairingCode("999999")!
    private let t1 = HexToken("11111111111111111111111111111111")!
    private let t2 = HexToken("22222222222222222222222222222222")!
    private let t3 = HexToken("33333333333333333333333333333333")!
    private let t4 = HexToken("44444444444444444444444444444444")!
    private let t5 = HexToken("55555555555555555555555555555555")!

    private func makeViewModel(
        timeout: Duration = .seconds(25),
        pairingTimeout: Duration = .seconds(60),
        throttle: CommandThrottle = CommandThrottle(maxCommands: 10, window: .seconds(1)),
        clock: @escaping () -> ContinuousClock.Instant = { .now }
    ) -> (PresentationViewModel, () -> Int) {
        var tokens = [t1, t2, t3, t4, t5]
        var queue = [first, second, PairingCode("333333")!, PairingCode("444444")!]
        var calls = 0
        let viewModel = PresentationViewModel(
            receiver: receiver,
            pdfLoader: StubPDFLoader(),
            invitationTimeout: timeout,
            pairingTimeout: pairingTimeout,
            throttle: throttle,
            clock: clock,
            tokenGenerator: { tokens.isEmpty ? HexToken.generate() : tokens.removeFirst() },
            codeGenerator: {
                calls += 1
                return queue.isEmpty ? PairingCode.generate() : queue.removeFirst()
            }
        )
        return (viewModel, { calls })
    }

    private func connectApproved(_ viewModel: PresentationViewModel, name: String = "iPhone da Clara") {
        receiver.simulateInvitation(from: name)
        viewModel.respondToInvitation(accept: true)
        receiver.simulateConnection(true)
    }

    private func loadPDF(_ viewModel: PresentationViewModel) {
        viewModel.loadPDF(from: URL(fileURLWithPath: "/tmp/x.pdf"))
    }

    // MARK: - Invitation

    @Test func startsTheReceiver() {
        _ = makeViewModel()
        #expect(receiver.started)
    }

    @Test func invitationShowsPendingPeerName() {
        let (viewModel, _) = makeViewModel()
        receiver.simulateInvitation(from: "iPhone da Clara")
        #expect(viewModel.pendingInvitation == "iPhone da Clara")
        #expect(viewModel.pairingCode == nil)
    }

    @Test func invitationWhileAnotherPeerIsActiveIsRejectedWithoutAlert() {
        let (viewModel, _) = makeViewModel()
        connectApproved(viewModel)
        receiver.simulateInvitation(from: "Intruso")
        #expect(receiver.autoRejectedInvitations == 1)
        #expect(viewModel.pendingInvitation == nil)
    }

    @Test func acceptingInvitationCreatesFreshCode() {
        let (viewModel, calls) = makeViewModel()
        receiver.simulateInvitation(from: "iPhone")
        viewModel.respondToInvitation(accept: true)
        #expect(receiver.responses == [true])
        #expect(viewModel.pendingInvitation == nil)
        #expect(viewModel.pairingCode == first)
        #expect(calls() == 1)
        #expect(!viewModel.isAuthenticated)
    }

    @Test func decliningInvitationCreatesNoSession() {
        let (viewModel, calls) = makeViewModel()
        receiver.simulateInvitation(from: "iPhone")
        viewModel.respondToInvitation(accept: false)
        #expect(receiver.responses == [false])
        #expect(viewModel.pendingInvitation == nil)
        #expect(viewModel.pairingCode == nil)
        #expect(calls() == 0)
    }

    @Test func respondingWithoutPendingInvitationDoesNothing() {
        let (viewModel, calls) = makeViewModel()
        viewModel.respondToInvitation(accept: true)
        #expect(receiver.responses.isEmpty)
        #expect(viewModel.pairingCode == nil)
        #expect(calls() == 0)
    }

    @Test func unansweredInvitationIsDeclinedAfterTimeout() async throws {
        let (viewModel, _) = makeViewModel(timeout: .milliseconds(30))
        receiver.simulateInvitation(from: "iPhone")
        try await Task.sleep(for: .milliseconds(300))
        #expect(receiver.responses == [false])
        #expect(viewModel.pendingInvitation == nil)
        #expect(viewModel.pairingCode == nil)
    }

    @Test func answeringBeforeTimeoutDoesNotDeclineLater() async throws {
        let (viewModel, _) = makeViewModel(timeout: .milliseconds(100))
        receiver.simulateInvitation(from: "iPhone")
        viewModel.respondToInvitation(accept: true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(receiver.responses == [true])
        #expect(viewModel.pairingCode == first)
    }

    // MARK: - Commands and pairing

    @Test func connectedWithoutCodeIsNotAuthenticated() {
        let (viewModel, _) = makeViewModel()
        connectApproved(viewModel)
        #expect(viewModel.isConnected)
        #expect(!viewModel.isAuthenticated)
        #expect(viewModel.pairingCode == first)
    }

    @Test func commandBeforeAuthenticationIsIgnored() {
        let (viewModel, _) = makeViewModel()
        loadPDF(viewModel)
        connectApproved(viewModel)
        receiver.simulate(.command(.next))
        #expect(viewModel.presentation?.currentIndex == 0)
    }

    @Test func wrongCodeIsRejectedWithAttemptsLeft() {
        let (viewModel, _) = makeViewModel()
        connectApproved(viewModel)
        receiver.simulate(.pair(wrong))
        #expect(receiver.sent == [.pairingResult(.rejected(attemptsLeft: 2))])
        #expect(!viewModel.isAuthenticated)
    }

    @Test func correctCodeAuthenticatesAndCommandsApply() {
        let (viewModel, _) = makeViewModel()
        loadPDF(viewModel)
        connectApproved(viewModel)
        receiver.simulate(.pair(first))
        #expect(receiver.sent == [.pairingResult(.accepted), .credential(t1)])
        #expect(viewModel.isAuthenticated)
        receiver.simulate(.command(.next))
        #expect(viewModel.presentation?.currentIndex == 1)
    }

    @Test func threeWrongCodesLockDisconnectAndRenewCode() {
        let (viewModel, calls) = makeViewModel()
        connectApproved(viewModel)
        receiver.simulate(.pair(wrong))
        receiver.simulate(.pair(wrong))
        receiver.simulate(.pair(wrong))
        #expect(receiver.sent.last == .pairingResult(.locked))
        #expect(receiver.disconnectCount == 1)
        #expect(calls() == 2)
        #expect(viewModel.pairingCode == second)
        #expect(!viewModel.isAuthenticated)
    }

    @Test func oldCodeDoesNotWorkAfterLock() {
        let (viewModel, _) = makeViewModel()
        connectApproved(viewModel)
        for _ in 0..<3 { receiver.simulate(.pair(wrong)) }
        receiver.simulate(.pair(first))
        #expect(!viewModel.isAuthenticated)
    }

    @Test func connectionDropResetsAuthenticationAndCode() {
        let (viewModel, calls) = makeViewModel()
        loadPDF(viewModel)
        connectApproved(viewModel)
        receiver.simulate(.pair(first))
        receiver.simulateConnection(false)
        #expect(!viewModel.isConnected)
        #expect(!viewModel.isAuthenticated)
        #expect(viewModel.pairingCode == nil)

        receiver.simulate(.command(.next))
        #expect(viewModel.presentation?.currentIndex == 0)

        connectApproved(viewModel)
        #expect(viewModel.pairingCode == second)
        #expect(calls() == 2)
        #expect(!viewModel.isAuthenticated)
    }

    @Test func pairMessageWithoutSessionIsIgnored() {
        let (viewModel, _) = makeViewModel()
        receiver.simulate(.pair(first))
        #expect(receiver.sent.isEmpty)
        #expect(!viewModel.isAuthenticated)
    }

    @Test func invalidPayloadIsDiscardedByTheDecoder() {
        // The receiver discards what doesn't decode; here we ensure the decoder rejects garbage.
        #expect(RemoteMessage(data: Data("lixo".utf8)) == nil)
        #expect(RemoteMessage(data: Data([0xFF, 0xFE])) == nil)
    }

    @Test func pairingResultFromPeerIsIgnored() {
        let (viewModel, _) = makeViewModel()
        connectApproved(viewModel)
        receiver.simulate(.pairingResult(.accepted))
        #expect(!viewModel.isAuthenticated)
        #expect(receiver.sent.isEmpty)
    }

    // MARK: - Pairing deadline and manual disconnect

    @Test func approvedButNeverConnectedIsReleasedAfterPairingTimeout() async throws {
        let (viewModel, _) = makeViewModel(pairingTimeout: .milliseconds(50))
        receiver.simulateInvitation(from: "iPhone")
        viewModel.respondToInvitation(accept: true)
        try await Task.sleep(for: .milliseconds(400))
        #expect(receiver.disconnectCount == 1)
        #expect(viewModel.pairingCode == nil)
        #expect(!viewModel.isAuthenticated)
    }

    @Test func connectedWithoutCodeIsDisconnectedAfterPairingTimeout() async throws {
        let (viewModel, _) = makeViewModel(pairingTimeout: .milliseconds(50))
        connectApproved(viewModel)
        try await Task.sleep(for: .milliseconds(400))
        #expect(receiver.disconnectCount == 1)
        #expect(viewModel.pairingCode == nil)
        #expect(!viewModel.isConnected)
    }

    @Test func authenticatingBeforeTheDeadlineKeepsTheConnection() async throws {
        let (viewModel, _) = makeViewModel(pairingTimeout: .milliseconds(100))
        connectApproved(viewModel)
        receiver.simulate(.pair(first))
        try await Task.sleep(for: .milliseconds(400))
        #expect(receiver.disconnectCount == 0)
        #expect(viewModel.isAuthenticated)
        #expect(viewModel.isConnected)
    }

    @Test func connectionDropCancelsThePairingDeadline() async throws {
        let (viewModel, _) = makeViewModel(pairingTimeout: .milliseconds(100))
        connectApproved(viewModel)
        receiver.simulateConnection(false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(receiver.disconnectCount == 0)
        _ = viewModel
    }

    @Test func lockingTheSessionCancelsThePairingDeadline() async throws {
        let (viewModel, _) = makeViewModel(pairingTimeout: .milliseconds(100))
        connectApproved(viewModel)
        for _ in 0..<3 { receiver.simulate(.pair(wrong)) }
        #expect(receiver.disconnectCount == 1)
        try await Task.sleep(for: .milliseconds(400))
        #expect(receiver.disconnectCount == 1)
        _ = viewModel
    }

    @Test func disconnectingThePhoneEndsAnAuthenticatedSession() {
        let (viewModel, _) = makeViewModel()
        loadPDF(viewModel)
        connectApproved(viewModel)
        receiver.simulate(.pair(first))
        viewModel.disconnectPhone()

        #expect(receiver.disconnectCount == 1)
        #expect(!viewModel.isConnected)
        #expect(!viewModel.isAuthenticated)
        #expect(viewModel.pairingCode == nil)

        receiver.simulate(.command(.next))
        #expect(viewModel.presentation?.currentIndex == 0)
    }

    @Test func disconnectingThePhoneReleasesAnApprovedPeerThatNeverConnected() {
        let (viewModel, _) = makeViewModel()
        receiver.simulateInvitation(from: "iPhone")
        viewModel.respondToInvitation(accept: true)
        viewModel.disconnectPhone()

        #expect(receiver.disconnectCount == 1)
        #expect(viewModel.pairingCode == nil)
    }

    @Test func disconnectingWithNobodyAroundDoesNothing() {
        let (viewModel, _) = makeViewModel()
        viewModel.disconnectPhone()
        #expect(receiver.disconnectCount == 0)
    }

    // MARK: - Rate limit

    @Test func commandsAboveTheRateLimitAreDropped() {
        var now = ContinuousClock.now
        let (viewModel, _) = makeViewModel(
            throttle: CommandThrottle(maxCommands: 1, window: .seconds(1)),
            clock: { now }
        )
        loadPDF(viewModel)
        connectApproved(viewModel)
        receiver.simulate(.pair(first))

        receiver.simulate(.command(.next))
        receiver.simulate(.command(.next))
        #expect(viewModel.presentation?.currentIndex == 1)

        now = now.advanced(by: .seconds(1))
        receiver.simulate(.command(.next))
        #expect(viewModel.presentation?.currentIndex == 2)
    }

    @Test func eachNewSessionStartsWithAFreshRateLimit() {
        let now = ContinuousClock.now
        let (viewModel, _) = makeViewModel(
            throttle: CommandThrottle(maxCommands: 1, window: .seconds(1)),
            clock: { now }
        )
        loadPDF(viewModel)
        connectApproved(viewModel)
        receiver.simulate(.pair(first))
        receiver.simulate(.command(.next))
        receiver.simulate(.command(.next))
        #expect(viewModel.presentation?.currentIndex == 1)

        receiver.simulateConnection(false)
        connectApproved(viewModel)
        receiver.simulate(.pair(second))
        receiver.simulate(.command(.next))
        #expect(viewModel.presentation?.currentIndex == 2)
    }

    @Test func droppedCommandsDoNotAffectPairing() {
        let now = ContinuousClock.now
        let (viewModel, _) = makeViewModel(
            throttle: CommandThrottle(maxCommands: 1, window: .seconds(1)),
            clock: { now }
        )
        connectApproved(viewModel)
        receiver.simulate(.pair(first))
        receiver.simulate(.command(.next))
        receiver.simulate(.command(.next))
        #expect(viewModel.isAuthenticated)
        #expect(viewModel.isConnected)
    }

    // MARK: - Session resume (in-memory credential)

    /// Pairs with the code and returns the already-authenticated viewModel (credential `t1` issued).
    private func pairWithCode(_ viewModel: PresentationViewModel) {
        connectApproved(viewModel)
        receiver.simulate(.pair(first))
    }

    private func reconnectApproved(_ viewModel: PresentationViewModel) {
        receiver.simulateConnection(false)
        connectApproved(viewModel)
    }

    @Test func acceptedCodeIssuesACredentialInsideTheSession() {
        let (viewModel, _) = makeViewModel()
        pairWithCode(viewModel)
        #expect(receiver.sent == [.pairingResult(.accepted), .credential(t1)])
        #expect(viewModel.isAuthenticated)
    }

    @Test func wrongCodeDoesNotIssueACredential() {
        let (viewModel, _) = makeViewModel()
        connectApproved(viewModel)
        receiver.simulate(.pair(wrong))
        #expect(receiver.sent == [.pairingResult(.rejected(attemptsLeft: 2))])
        _ = viewModel
    }

    @Test func resumeWithoutACredentialIsRejected() {
        let (viewModel, _) = makeViewModel()
        connectApproved(viewModel)
        receiver.simulate(.resumeRequest)
        #expect(receiver.sent == [.resumeRejected])
        #expect(!viewModel.isAuthenticated)
    }

    @Test func resumeWithoutAnApprovedInvitationIsRejected() {
        let (viewModel, _) = makeViewModel()
        pairWithCode(viewModel)
        receiver.simulateConnection(false)
        let before = receiver.sent.count
        receiver.simulate(.resumeRequest)
        #expect(Array(receiver.sent.dropFirst(before)) == [.resumeRejected])
        #expect(!viewModel.isAuthenticated)
    }

    @Test func resumeAfterADropIssuesAChallenge() {
        let (viewModel, _) = makeViewModel()
        pairWithCode(viewModel)
        reconnectApproved(viewModel)
        receiver.simulate(.resumeRequest)
        #expect(receiver.sent.last == .resumeChallenge(t2))
        #expect(!viewModel.isAuthenticated)
    }

    @Test func validProofAuthenticatesWithoutTheCodeAndRotatesTheCredential() {
        let (viewModel, _) = makeViewModel()
        loadPDF(viewModel)
        pairWithCode(viewModel)
        reconnectApproved(viewModel)
        receiver.simulate(.resumeRequest)
        let before = receiver.sent.count

        receiver.simulate(.resumeProof(ResumeProof.compute(credential: t1, nonce: t2)))

        #expect(viewModel.isAuthenticated)
        #expect(Array(receiver.sent.dropFirst(before)) == [.pairingResult(.accepted), .credential(t3)])
        receiver.simulate(.command(.next))
        #expect(viewModel.presentation?.currentIndex == 1)
    }

    @Test func invalidProofIsRejectedAndDoesNotAuthenticate() {
        let (viewModel, _) = makeViewModel()
        loadPDF(viewModel)
        pairWithCode(viewModel)
        reconnectApproved(viewModel)
        receiver.simulate(.resumeRequest)

        receiver.simulate(.resumeProof(ResumeProof.compute(credential: t5, nonce: t2)))

        #expect(receiver.sent.last == .resumeRejected)
        #expect(!viewModel.isAuthenticated)
        receiver.simulate(.command(.next))
        #expect(viewModel.presentation?.currentIndex == 0)
    }

    @Test func proofWithoutAPendingChallengeIsRejected() {
        let (viewModel, _) = makeViewModel()
        pairWithCode(viewModel)
        reconnectApproved(viewModel)
        receiver.simulate(.resumeProof(ResumeProof.compute(credential: t1, nonce: t2)))
        #expect(receiver.sent.last == .resumeRejected)
        #expect(!viewModel.isAuthenticated)
    }

    @Test func aChallengeCanOnlyBeAnsweredOnce() {
        let (viewModel, _) = makeViewModel()
        pairWithCode(viewModel)
        reconnectApproved(viewModel)
        receiver.simulate(.resumeRequest)
        receiver.simulate(.resumeProof(ResumeProof.compute(credential: t5, nonce: t2))) // wrong, consumes the challenge
        receiver.simulate(.resumeProof(ResumeProof.compute(credential: t1, nonce: t2))) // right, but too late
        #expect(receiver.sent.last == .resumeRejected)
        #expect(!viewModel.isAuthenticated)
    }

    @Test func rotatedCredentialInvalidatesTheOldOne() {
        let (viewModel, _) = makeViewModel()
        pairWithCode(viewModel)                                  // credential t1
        reconnectApproved(viewModel)
        receiver.simulate(.resumeRequest)                        // challenge t2
        receiver.simulate(.resumeProof(ResumeProof.compute(credential: t1, nonce: t2))) // issues t3

        reconnectApproved(viewModel)
        receiver.simulate(.resumeRequest)                        // challenge t4
        receiver.simulate(.resumeProof(ResumeProof.compute(credential: t1, nonce: t4)))
        #expect(receiver.sent.last == .resumeRejected)
        #expect(!viewModel.isAuthenticated)
    }

    @Test func disconnectingThePhoneRevokesTheCredential() {
        let (viewModel, _) = makeViewModel()
        pairWithCode(viewModel)
        viewModel.disconnectPhone()
        connectApproved(viewModel)
        receiver.simulate(.resumeRequest)
        #expect(receiver.sent.last == .resumeRejected)
        #expect(!viewModel.isAuthenticated)
    }

    @Test func lockingTheSessionRevokesTheCredential() {
        let (viewModel, _) = makeViewModel()
        pairWithCode(viewModel)
        reconnectApproved(viewModel)
        for _ in 0..<3 { receiver.simulate(.pair(wrong)) }       // locks
        reconnectApproved(viewModel)
        receiver.simulate(.resumeRequest)
        #expect(receiver.sent.last == .resumeRejected)
        #expect(!viewModel.isAuthenticated)
    }

    @Test func connectionDropKeepsTheCredentialForTheNextResume() {
        let (viewModel, _) = makeViewModel()
        pairWithCode(viewModel)
        reconnectApproved(viewModel)
        receiver.simulate(.resumeRequest)
        #expect(receiver.sent.last == .resumeChallenge(t2))
        _ = viewModel
    }

    @Test func resumeWhileAlreadyAuthenticatedIsIgnored() {
        let (viewModel, _) = makeViewModel()
        pairWithCode(viewModel)
        let before = receiver.sent.count
        receiver.simulate(.resumeRequest)
        #expect(receiver.sent.count == before)
        #expect(viewModel.isAuthenticated)
    }

    @Test func resumingBeforeTheDeadlineKeepsTheConnection() async throws {
        let (viewModel, _) = makeViewModel(pairingTimeout: .milliseconds(150))
        pairWithCode(viewModel)
        reconnectApproved(viewModel)
        receiver.simulate(.resumeRequest)
        receiver.simulate(.resumeProof(ResumeProof.compute(credential: t1, nonce: t2)))
        let disconnectsBefore = receiver.disconnectCount
        try await Task.sleep(for: .milliseconds(500))
        #expect(receiver.disconnectCount == disconnectsBefore)
        #expect(viewModel.isAuthenticated)
    }
}
