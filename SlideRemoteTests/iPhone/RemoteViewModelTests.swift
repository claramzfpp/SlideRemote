//
//  RemoteViewModelTests.swift
//  SlideRemoteTests
//

import Testing
import Combine
@testable import SlideRemote

@MainActor
private final class FakeSender: RemoteCommandSending {
    let peersSubject = CurrentValueSubject<[DiscoveredPeer], Never>([])
    let connectedSubject = CurrentValueSubject<Bool, Never>(false)

    var discoveredPeers: [DiscoveredPeer] { peersSubject.value }
    var discoveredPeersPublisher: AnyPublisher<[DiscoveredPeer], Never> { peersSubject.eraseToAnyPublisher() }
    var isConnected: Bool { connectedSubject.value }
    var isConnectedPublisher: AnyPublisher<Bool, Never> { connectedSubject.eraseToAnyPublisher() }
    var onMessage: ((RemoteMessage) -> Void)?

    private(set) var connectRequests: [DiscoveredPeer] = []
    private(set) var disconnectCount = 0
    private(set) var sent: [RemoteMessage] = []

    func connect(to peer: DiscoveredPeer) { connectRequests.append(peer) }
    func disconnect() { disconnectCount += 1 }
    func send(_ message: RemoteMessage) { sent.append(message) }

    func receive(_ message: RemoteMessage) { onMessage?(message) }
    func setConnected(_ value: Bool) { connectedSubject.send(value) }
}

@MainActor
private final class FakeMovementSource: MovementSource {
    var onMovementReceived: (() -> Void)?
}

@MainActor
struct RemoteViewModelTests {
    private let ipad = DiscoveredPeer(id: "ipad-1", name: "iPad da Sala")
    private let sender = FakeSender()
    private let movement = FakeMovementSource()
    private let viewModel: RemoteViewModel

    init() {
        viewModel = RemoteViewModel(sender: sender, movementSource: movement)
    }

    private func reachEnteringCode() {
        sender.peersSubject.send([ipad])
        viewModel.select(ipad)
        sender.setConnected(true)
    }

    private func reachVerifying() {
        reachEnteringCode()
        viewModel.submitCode("123456")
    }

    private func reachPaired() {
        reachVerifying()
        sender.receive(.pairingResult(.accepted))
    }

    @Test func startsSearchingWithNoPeers() {
        #expect(viewModel.phase == .searching)
        #expect(viewModel.peers.isEmpty)
    }

    @Test func showsDiscoveredPeersWhileSearching() {
        sender.peersSubject.send([ipad])
        #expect(viewModel.peers == [ipad])
        sender.peersSubject.send([])
        #expect(viewModel.peers.isEmpty)
    }

    @Test func selectingPeerStartsConnecting() {
        sender.peersSubject.send([ipad])
        viewModel.select(ipad)
        #expect(viewModel.phase == .connecting(peerName: "iPad da Sala"))
        #expect(sender.connectRequests == [ipad])
    }

    @Test func connectionEstablishedAsksForCode() {
        reachEnteringCode()
        #expect(viewModel.phase == .enteringCode(attemptsLeft: nil))
    }

    @Test func invalidFormatSendsNothingAndShowsError() {
        reachEnteringCode()
        viewModel.submitCode("12345")
        #expect(sender.sent.isEmpty)
        #expect(viewModel.codeError == "Digite os 6 dígitos")
        #expect(viewModel.phase == .enteringCode(attemptsLeft: nil))
    }

    @Test func validCodeSendsPairAndVerifies() {
        reachEnteringCode()
        viewModel.submitCode("123456")
        #expect(sender.sent == [.pair(PairingCode("123456")!)])
        #expect(viewModel.phase == .verifying)
        #expect(viewModel.codeError == nil)
    }

    @Test func acceptedPairs() {
        reachPaired()
        #expect(viewModel.phase == .paired)
    }

    @Test func rejectedReturnsToCodeEntryWithAttempts() {
        reachVerifying()
        sender.receive(.pairingResult(.rejected(attemptsLeft: 2)))
        #expect(viewModel.phase == .enteringCode(attemptsLeft: 2))
    }

    @Test func lockedReturnsToSearchingWithMessage() {
        reachVerifying()
        sender.receive(.pairingResult(.locked))
        #expect(viewModel.phase == .searching)
        #expect(viewModel.notice == "Pareamento bloqueado. Peça um novo código no iPad.")
    }

    @Test func dropWhileEnteringCodeReturnsToSearching() {
        reachEnteringCode()
        sender.setConnected(false)
        #expect(viewModel.phase == .searching)
        #expect(viewModel.notice == "Conexão perdida")
    }

    @Test func dropWhileVerifyingReturnsToSearching() {
        reachVerifying()
        sender.setConnected(false)
        #expect(viewModel.phase == .searching)
        #expect(viewModel.notice == "Conexão perdida")
    }

    @Test func dropWhilePairedReturnsToSearching() {
        reachPaired()
        sender.setConnected(false)
        #expect(viewModel.phase == .searching)
        #expect(viewModel.notice == "Conexão perdida")
    }

    @Test func refusedInvitationReturnsToSearchingWithMessage() {
        sender.peersSubject.send([ipad])
        viewModel.select(ipad)
        sender.setConnected(false)
        #expect(viewModel.phase == .searching)
        #expect(viewModel.notice == "O iPad recusou ou não respondeu")
    }

    @Test func cancelWhileConnectingDisconnectsQuietly() {
        sender.peersSubject.send([ipad])
        viewModel.select(ipad)
        viewModel.cancelConnection()
        #expect(viewModel.phase == .searching)
        #expect(sender.disconnectCount == 1)
        #expect(viewModel.notice == nil)
    }

    @Test func arrowsSendOnlyWhenPaired() {
        viewModel.next()
        reachEnteringCode()
        viewModel.previous()
        #expect(sender.sent.isEmpty)

        viewModel.submitCode("123456")
        viewModel.next()
        #expect(sender.sent == [.pair(PairingCode("123456")!)])

        sender.receive(.pairingResult(.accepted))
        viewModel.next()
        viewModel.previous()
        #expect(sender.sent.suffix(2) == [.command(.next), .command(.previous)])
    }

    @Test func watchMovementSendsNextOnlyWhenPaired() {
        viewModel.startListeningToWatch()
        movement.onMovementReceived?()
        #expect(sender.sent.isEmpty)

        reachPaired()
        movement.onMovementReceived?()
        #expect(sender.sent.last == .command(.next))
    }

    @Test func stopListeningClearsWatchHandler() {
        viewModel.startListeningToWatch()
        viewModel.stopListeningToWatch()
        #expect(movement.onMovementReceived == nil)
    }

    @Test func submitOutsideEnteringCodeIsIgnored() {
        viewModel.submitCode("123456")
        #expect(sender.sent.isEmpty)
        #expect(viewModel.phase == .searching)

        reachVerifying()
        viewModel.submitCode("654321")
        #expect(sender.sent.count == 1)

        sender.receive(.pairingResult(.accepted))
        viewModel.submitCode("654321")
        #expect(sender.sent.count == 1)
        #expect(viewModel.phase == .paired)
    }

    @Test func selectingOutsideSearchingIsIgnored() {
        reachEnteringCode()
        viewModel.select(ipad)
        #expect(sender.connectRequests.count == 1)
        #expect(viewModel.phase == .enteringCode(attemptsLeft: nil))
    }

    // MARK: - Retomada sem código

    private let credential = HexToken("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")!
    private let rotated = HexToken("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")!
    private let nonce = HexToken("cccccccccccccccccccccccccccccccc")!
    private let otherNonce = HexToken("dddddddddddddddddddddddddddddddd")!

    private func pairAndStoreCredential() {
        reachPaired()
        sender.receive(.credential(credential))
    }

    private func dropAndReconnect(to peer: DiscoveredPeer? = nil) {
        sender.setConnected(false)
        viewModel.select(peer ?? ipad)
        sender.setConnected(true)
    }

    @Test func reconnectingToAKnownIPadResumesInsteadOfAskingForTheCode() {
        pairAndStoreCredential()
        dropAndReconnect()
        #expect(viewModel.phase == .verifying)
        #expect(sender.sent.last == .resumeRequest)
    }

    @Test func reconnectingToADifferentIPadAsksForTheCode() {
        pairAndStoreCredential()
        dropAndReconnect(to: DiscoveredPeer(id: "ipad-2", name: "Outro iPad"))
        #expect(viewModel.phase == .enteringCode(attemptsLeft: nil))
    }

    @Test func aCredentialReceivedOutsidePairingIsIgnored() {
        sender.receive(.credential(credential))
        reachEnteringCode()
        #expect(viewModel.phase == .enteringCode(attemptsLeft: nil))
    }

    @Test func theChallengeIsAnsweredWithAProofAndNeverTheCredential() {
        pairAndStoreCredential()
        dropAndReconnect()
        sender.receive(.resumeChallenge(nonce))

        #expect(sender.sent.last == .resumeProof(ResumeProof.compute(credential: credential, nonce: nonce)))
        let everythingSent = sender.sent.map { String(decoding: $0.data, as: UTF8.self) }.joined()
        #expect(!everythingSent.contains(credential.value))
    }

    @Test func aChallengeOutsideAResumeIsIgnored() {
        reachVerifying()
        let before = sender.sent.count
        sender.receive(.resumeChallenge(nonce))
        #expect(sender.sent.count == before)
    }

    @Test func acceptedResumePairsAndTheRotatedCredentialIsUsedNext() {
        pairAndStoreCredential()
        dropAndReconnect()
        sender.receive(.resumeChallenge(nonce))
        sender.receive(.pairingResult(.accepted))
        sender.receive(.credential(rotated))
        #expect(viewModel.phase == .paired)

        dropAndReconnect()
        sender.receive(.resumeChallenge(otherNonce))
        #expect(sender.sent.last == .resumeProof(ResumeProof.compute(credential: rotated, nonce: otherNonce)))
    }

    @Test func rejectedResumeFallsBackToTheCodeAndForgetsTheCredential() {
        pairAndStoreCredential()
        dropAndReconnect()
        sender.receive(.resumeRejected)
        #expect(viewModel.phase == .enteringCode(attemptsLeft: nil))
        #expect(viewModel.codeError != nil)

        dropAndReconnect()
        #expect(viewModel.phase == .enteringCode(attemptsLeft: nil))
    }

    @Test func lockedForgetsTheCredential() {
        pairAndStoreCredential()
        dropAndReconnect()
        sender.receive(.pairingResult(.locked))
        #expect(viewModel.phase == .searching)

        viewModel.select(ipad)
        sender.setConnected(true)
        #expect(viewModel.phase == .enteringCode(attemptsLeft: nil))
    }

    @Test func aResumeRejectionOutsideAResumeIsIgnored() {
        reachVerifying()
        sender.receive(.resumeRejected)
        #expect(viewModel.phase == .verifying)
    }

    @Test func commandsAreBlockedWhileResuming() {
        pairAndStoreCredential()
        dropAndReconnect()
        let before = sender.sent.count
        viewModel.next()
        viewModel.previous()
        #expect(sender.sent.count == before)
    }

    @Test func aDropWhileResumingKeepsTheCredential() {
        pairAndStoreCredential()
        dropAndReconnect()
        sender.setConnected(false)
        #expect(viewModel.phase == .searching)
        #expect(viewModel.notice == "Conexão perdida")

        viewModel.select(ipad)
        sender.setConnected(true)
        #expect(viewModel.phase == .verifying)
        #expect(sender.sent.last == .resumeRequest)
    }
}
