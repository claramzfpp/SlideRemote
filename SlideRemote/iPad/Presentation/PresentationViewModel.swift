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

    private var session: PairingSession?
    private var invitationTimeoutTask: Task<Void, Never>?
    private var pairingDeadlineTask: Task<Void, Never>?

    init(
        receiver: CommandReceiving,
        pdfLoader: PDFLoading,
        invitationTimeout: Duration = .seconds(25),
        pairingTimeout: Duration = .seconds(60),
        codeGenerator: @escaping () -> PairingCode = { PairingCode.generate() }
    ) {
        self.receiver = receiver
        self.pdfLoader = pdfLoader
        self.invitationTimeout = invitationTimeout
        self.pairingTimeout = pairingTimeout
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
            presentation?.apply(command)
        case .pairingResult: break // mensagem do iPad para o iPhone; ignorada se vier de volta
        }
    }

    private func handlePairing(_ attempt: PairingCode) {
        guard var current = session else { return }
        let result = current.submit(attempt)
        session = current
        receiver.send(.pairingResult(result))

        switch result {
        case .accepted:
            isAuthenticated = true
            pairingDeadlineTask?.cancel()
        case .rejected:
            break
        case .locked:
            pairingDeadlineTask?.cancel()
            receiver.disconnectPeer()
            startNewSession()
        }
    }

    // MARK: - Sessão

    private func startNewSession() {
        let code = codeGenerator()
        session = PairingSession(code: code)
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
        session = nil
        pairingCode = nil
        isAuthenticated = false
    }
}
