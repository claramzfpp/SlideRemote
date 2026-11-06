//
//  ResumeProof.swift
//  SlideRemote
//

import CryptoKit
import Foundation

/// Proof that the iPhone still has the credential, without sending it: HMAC-SHA256(credential, challenge).
/// A fake iPad that receives the proof for its own challenge can't reuse it or discover the credential.
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
