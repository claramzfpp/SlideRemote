//
//  ResumeProof.swift
//  SlideRemote
//

import CryptoKit
import Foundation

/// Prova de que o iPhone ainda tem a credencial, sem enviá-la: HMAC-SHA256(credencial, desafio).
/// Um iPad falso que receba a prova de um desafio dele não consegue reaproveitá-la nem descobrir a credencial.
struct ResumeProof: Equatable, Sendable {
    static let length = 64

    let value: String

    init?(_ value: String) {
        guard isLowercaseHex(value, length: Self.length) else { return nil }
        self.value = value
    }

    static func compute(credential: HexToken, nonce: HexToken) -> ResumeProof {
        let key = SymmetricKey(data: Data(credential.value.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(nonce.value.utf8), using: key)
        return ResumeProof(mac.map { String(format: "%02x", $0) }.joined())!
    }

    func matches(_ other: ResumeProof) -> Bool {
        constantTimeEquals(value, other.value)
    }
}
