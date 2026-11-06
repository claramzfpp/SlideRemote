//
//  PresentationViewModel.swift
//  SlideRemote
//
//  Orquestra o iPad: carrega o PDF, pareia o iPhone e aplica os comandos autenticados.
//

import Foundation
import PDFKit
import Combine

@MainActor
final class PresentationViewModel: ObservableObject {
    @Published private(set) var document: PDFDocument?
    @Published private(set) var presentation: Presentation?
    @Published private(set) var isConnected = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var loadError: String?
    /// Name of the iPhone awaiting permission.
    @Published private(set) var pendingInvitation: String?
    /// Code the iPhone must type; nil when no peer has been approved.
    @Published private(set) var pairingCode: PairingCode?

    private let receiver: CommandReceiving
    private let pdfLoader: PDFLoading
    private let codeGenerator: () -> PairingCode
    private let invitationTimeout: Duration
    private let pairingTimeout: Duration
    private let throttleTemplate: CommandThrottle
    private let clock: () -> ContinuousClock.Instant
    private let tokenGenerator: () -> HexToken

    private var session: PairingSession?
    private var throttle: CommandThrottle
    /// Reconnect credential: in memory only, never persisted. It disappears when the app closes, when the presenter disconnects the iPhone or when the session locks.
    private var credential: HexToken?
    private var pendingChallenge: HexToken?
    private var invitationTimeoutTask: Task<Void, Never>?
    private var pairingDeadlineTask: Task<Void, Never>?

    init(
        receiver: CommandReceiving,
        pdfLoader: PDFLoading,
        invitationTimeout: Duration = .seconds(25),
        pairingTimeout: Duration = .seconds(60),
        throttle: CommandThrottle = CommandThrottle(maxCommands: 10, window: .seconds(1)),
        clock: @escaping () -> ContinuousClock.Instant = { .now },
        tokenGenerator: @escaping () -> HexToken = { HexToken.generate() },
        codeGenerator: @escaping () -> PairingCode = { PairingCode.generate() }
    ) {
        self.receiver = receiver
        self.pdfLoader = pdfLoader
        self.invitationTimeout = invitationTimeout
        self.pairingTimeout = pairingTimeout
        self.throttleTemplate = throttle
        self.throttle = throttle
        self.clock = clock
        self.tokenGenerator = tokenGenerator
        self.codeGenerator = codeGenerator

        receiver.onInvitation = { [weak self] name in self?.handleInvitation(from: name) }
        receiver.onMessage = { [weak self] message in self?.handle(message) }
        receiver.onConnectionChange = { [weak self] connected in self?.handleConnectionChange(connected) }
        receiver.start()
    }

    deinit {
        invitationTimeoutTask?.cancel()
        pairingDeadlineTask?.cancel()
    }

    func loadPDF(from url: URL) {
        do {
            let pdf = try pdfLoader.load(from: url)
            document = pdf
            presentation = Presentation(pageCount: pdf.pageCount)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func closePresentation() {
        document = nil
        presentation = nil
    }

    func respondToInvitation(accept: Bool) {
        guard pendingInvitation != nil else { return }
        invitationTimeoutTask?.cancel()
        pendingInvitation = nil
        receiver.respondToInvitation(accept: accept)
        if accept {
            startNewSession()
            startPairingDeadline()
        }
    }

    /// Ends the connection with the current iPhone (authenticated or not) and frees the slot for another invitation.
    func disconnectPhone() {
        guard session != nil || isConnected else { return }
        receiver.disconnectPeer()
        credential = nil
        endSession()
        isConnected = false
    }

    // MARK: - Receiver callbacks

    private func handleInvitation(from name: String) {
        pendingInvitation = name
        invitationTimeoutTask?.cancel()
        invitationTimeoutTask = Task { [weak self, invitationTimeout] in
            try? await Task.sleep(for: invitationTimeout)
            guard !Task.isCancelled else { return }
            self?.respondToInvitation(accept: false)
        }
    }

    private func handleConnectionChange(_ connected: Bool) {
        isConnected = connected
        if !connected { endSession() }
    }

    private func handle(_ message: RemoteMessage) {
        switch message {
        case .pair(let attempt): handlePairing(attempt)
        case .command(let command):
            // Before authenticating, or without a PDF, there is nothing to apply.
            guard isAuthenticated else { return }
            // A peer (or bug) firing commands in a burst must not advance several slides at once.
            guard throttle.allow(at: clock()) else {
                AppLog.connectivity.notice("Comando descartado por limite de taxa")
                return
            }
            presentation?.apply(command)
        case .resumeRequest: handleResumeRequest()
        case .resumeProof(let proof): handleResumeProof(proof)
        case .pairingResult, .credential, .resumeChallenge, .resumeRejected:
            break // messages from the iPad to the iPhone; ignored if they come back
        }
    }

    private func handlePairing(_ attempt: PairingCode) {
        guard !isAuthenticated, var current = session else { return }
        let result = current.submit(attempt)
        session = current
        receiver.send(.pairingResult(result))

        switch result {
        case .accepted:
            authenticate()
        case .rejected:
            break
        case .locked:
            credential = nil
            pairingDeadlineTask?.cancel()
            receiver.disconnectPeer()
            startNewSession()
        }
    }

    // MARK: - Resume without code

    /// The iPhone asks to resume. Only valid for an invitation approved now (the alert still stands) and if there is a credential.
    private func handleResumeRequest() {
        guard !isAuthenticated else { return }
        guard session != nil, credential != nil else {
            receiver.send(.resumeRejected)
            return
        }
        let nonce = tokenGenerator()
        pendingChallenge = nonce
        receiver.send(.resumeChallenge(nonce))
    }

    /// Each challenge allows a single answer, right or wrong, so the proof can't be reused.
    private func handleResumeProof(_ proof: ResumeProof) {
        guard !isAuthenticated else { return }
        guard session != nil, let credential, let nonce = pendingChallenge else {
            receiver.send(.resumeRejected)
            return
        }
        pendingChallenge = nil
        guard ResumeProof.compute(credential: credential, nonce: nonce).matches(proof) else {
            receiver.send(.resumeRejected)
            return
        }
        receiver.send(.pairingResult(.accepted))
        authenticate()
    }

    /// Authenticates and rotates the credential: the previous one stops being valid as soon as the new one exists.
    private func authenticate() {
        isAuthenticated = true
        pairingDeadlineTask?.cancel()
        let fresh = tokenGenerator()
        credential = fresh
        receiver.send(.credential(fresh))
    }

    // MARK: - Session

    private func startNewSession() {
        let code = codeGenerator()
        session = PairingSession(code: code)
        throttle = throttleTemplate
        pairingCode = code
        isAuthenticated = false
    }

    /// Whoever was approved must authenticate within the deadline; otherwise the slot is released (including if the connection never completed).
    private func startPairingDeadline() {
        pairingDeadlineTask?.cancel()
        pairingDeadlineTask = Task { [weak self, pairingTimeout] in
            try? await Task.sleep(for: pairingTimeout)
            guard !Task.isCancelled else { return }
            self?.expirePairing()
        }
    }

    private func expirePairing() {
        guard !isAuthenticated else { return }
        disconnectPhone()
    }

    private func endSession() {
        pairingDeadlineTask?.cancel()
        pendingChallenge = nil
        session = nil
        pairingCode = nil
        isAuthenticated = false
    }
}
