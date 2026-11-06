//
//  ResumeProofTests.swift
//  SlideRemoteTests
//

import Testing
@testable import SlideRemote

struct ResumeProofTests {
    private let zeros = HexToken("00000000000000000000000000000000")!
    private let ones = HexToken("11111111111111111111111111111111")!

    @Test func matchesKnownHMACSHA256Vectors() throws {
        // Generated with: echo -n <nonce> | openssl dgst -sha256 -hmac <credential>
        #expect(ResumeProof.compute(credential: zeros, nonce: ones).value
                == "af46a312a09483576fda6c8b6dbee25b41c9f1fd23269385705797bf95c90d91")

        let credential = try #require(HexToken("0123456789abcdef0123456789abcdef"))
        let nonce = try #require(HexToken("abcdefabcdefabcdefabcdefabcdefab"))
        #expect(ResumeProof.compute(credential: credential, nonce: nonce).value
                == "8cf38de706e941f8646da5f72a17eb4220200cfcd07f42a73b931082f2fc63b4")
    }

    @Test func sameInputsGiveTheSameProof() {
        let a = ResumeProof.compute(credential: zeros, nonce: ones)
        let b = ResumeProof.compute(credential: zeros, nonce: ones)
        #expect(a.matches(b))
    }

    @Test func differentCredentialOrNonceChangeTheProof() {
        let base = ResumeProof.compute(credential: zeros, nonce: ones)
        #expect(!base.matches(ResumeProof.compute(credential: ones, nonce: ones)))
        #expect(!base.matches(ResumeProof.compute(credential: zeros, nonce: zeros)))
    }

    @Test func acceptsOnlySixtyFourLowercaseHexCharacters() {
        let valid = String(repeating: "a", count: 64)
        #expect(ResumeProof(valid)?.value == valid)
        #expect(ResumeProof(String(repeating: "a", count: 63)) == nil)
        #expect(ResumeProof(String(repeating: "a", count: 65)) == nil)
        #expect(ResumeProof(String(repeating: "A", count: 64)) == nil)
        #expect(ResumeProof(String(repeating: "g", count: 64)) == nil)
    }
}
