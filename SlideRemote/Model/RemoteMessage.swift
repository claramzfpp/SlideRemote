//
//  RemoteMessage.swift
//  SlideRemote
//
//  Everything exchanged between iPhone and iPad. The format is plain, closed text:
//  any payload outside the list is discarded.
//

import Foundation

enum RemoteMessage: Equatable, Sendable {
    case command(RemoteCommand)
    case pair(PairingCode)
    case pairingResult(PairingResult)

    /// iPad → iPhone, only after authenticating: credential to resume the session without typing the code.
    case credential(HexToken)
    /// iPhone → iPad: wants to resume using the credential.
    case resumeRequest
    /// iPad → iPhone: random challenge.
    case resumeChallenge(HexToken)
    /// iPhone → iPad: response to the challenge.
    case resumeProof(ResumeProof)
    /// iPad → iPhone: resume refused; enter the code.
    case resumeRejected

    private static let pairPrefix = "pair:"
    private static let resultPrefix = "pairing:"
    private static let credentialPrefix = "credential:"
    private static let challengePrefix = "challenge:"
    private static let proofPrefix = "proof:"
    private static let resumeRequestWire = "resume"
    private static let resumeRejectedWire = "resume:rejected"

    var data: Data { Data(wireString.utf8) }

    private var wireString: String {
        switch self {
        case .command(let command): command.rawValue
        case .pair(let code): Self.pairPrefix + code.value
        case .pairingResult(.accepted): Self.resultPrefix + "accepted"
        case .pairingResult(.locked): Self.resultPrefix + "locked"
        case .pairingResult(.rejected(let left)): Self.resultPrefix + "rejected:\(left)"
        case .credential(let token): Self.credentialPrefix + token.value
        case .resumeRequest: Self.resumeRequestWire
        case .resumeChallenge(let nonce): Self.challengePrefix + nonce.value
        case .resumeProof(let proof): Self.proofPrefix + proof.value
        case .resumeRejected: Self.resumeRejectedWire
        }
    }

    init?(data: Data) {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }

        if let command = RemoteCommand(rawValue: raw) {
            self = .command(command)
        } else if raw == Self.resumeRequestWire {
            self = .resumeRequest
        } else if raw == Self.resumeRejectedWire {
            self = .resumeRejected
        } else if let value = Self.payload(of: raw, prefix: Self.pairPrefix), let code = PairingCode(value) {
            self = .pair(code)
        } else if let value = Self.payload(of: raw, prefix: Self.resultPrefix), let result = Self.parseResult(value) {
            self = .pairingResult(result)
        } else if let value = Self.payload(of: raw, prefix: Self.credentialPrefix), let token = HexToken(value) {
            self = .credential(token)
        } else if let value = Self.payload(of: raw, prefix: Self.challengePrefix), let nonce = HexToken(value) {
            self = .resumeChallenge(nonce)
        } else if let value = Self.payload(of: raw, prefix: Self.proofPrefix), let proof = ResumeProof(value) {
            self = .resumeProof(proof)
        } else {
            return nil
        }
    }

    private static func payload(of raw: String, prefix: String) -> String? {
        raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : nil
    }

    private static func parseResult(_ raw: String) -> PairingResult? {
        switch raw {
        case "accepted": return .accepted
        case "locked": return .locked
        default:
            let rejected = "rejected:"
            guard raw.hasPrefix(rejected),
                  let left = Int(raw.dropFirst(rejected.count)), left >= 0 else { return nil }
            return .rejected(attemptsLeft: left)
        }
    }
}
