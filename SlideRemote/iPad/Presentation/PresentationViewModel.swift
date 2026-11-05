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
    /// Nome do iPhone aguardando permissão.
    @Published private(set) var pendingInvitation: String?
    /// Código que o iPhone precisa digitar; nil quando nenhum peer foi aprovado.
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
    /// Credencial de reconexão: só em memória, nunca gravada. Some quando o app fecha, quando o apresentador desconecta o iPhone ou quando a sessão trava.
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

    /// Encerra a conexão com o iPhone atual (autenticado ou não) e libera a vaga para outro convite.
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
            // Antes de autenticar, ou sem PDF, não há o que aplicar.
            guard isAuthenticated else { return }
            // Um peer (ou bug) que dispare comandos em rajada não pode passar vários slides de uma vez.
            guard throttle.allow(at: clock()) else {
                AppLog.connectivity.notice("Comando descartado por limite de taxa")
                return
            }
            presentation?.apply(command)
        case .resumeRequest: handleResumeRequest()
        case .resumeProof(let proof): handleResumeProof(proof)
        case .pairingResult, .credential, .resumeChallenge, .resumeRejected:
            break // mensagens do iPad para o iPhone; ignoradas se vierem de volta
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

    // MARK: - Retomada sem código

    /// O iPhone pede para retomar. Só vale para um convite aprovado agora (o alerta continua valendo) e se houver credencial.
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

    /// Cada desafio vale uma única resposta, certa ou errada, para a prova não poder ser reaproveitada.
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

    /// Autentica e troca a credencial: a anterior deixa de valer assim que a nova existe.
    private func authenticate() {
        isAuthenticated = true
        pairingDeadlineTask?.cancel()
        let fresh = tokenGenerator()
        credential = fresh
        receiver.send(.credential(fresh))
    }

    // MARK: - Sessão

    private func startNewSession() {
        let code = codeGenerator()
        session = PairingSession(code: code)
        throttle = throttleTemplate
        pairingCode = code
        isAuthenticated = false
    }

    /// Quem foi aprovado precisa autenticar dentro do prazo; senão a vaga é liberada (inclusive se a conexão nunca completou).
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
