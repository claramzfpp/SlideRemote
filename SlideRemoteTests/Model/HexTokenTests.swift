//
//  HexTokenTests.swift
//  SlideRemoteTests
//

import Testing
@testable import SlideRemote

struct HexTokenTests {
    @Test func acceptsThirtyTwoLowercaseHexCharacters() {
        #expect(HexToken("0123456789abcdef0123456789abcdef")?.value == "0123456789abcdef0123456789abcdef")
    }

    @Test(arguments: [
        "", "0123456789abcdef", "0123456789abcdef0123456789abcdef0",
        "0123456789ABCDEF0123456789ABCDEF", "0123456789abcdef0123456789abcdeg",
        "0123456789abcdef0123456789abcde ", "٠١٢٣٤٥٦٧٨٩abcdef0123456789abcdef"
    ])
    func rejectsInvalidFormats(_ input: String) {
        #expect(HexToken(input) == nil)
    }

    @Test func generatedTokensAreValidAndDifferent() throws {
        let a = HexToken.generate()
        let b = HexToken.generate()
        #expect(HexToken(a.value) != nil)
        #expect(!a.matches(b))
    }

    @Test func equalTokensMatch() throws {
        let a = try #require(HexToken("00000000000000000000000000000001"))
        let b = try #require(HexToken("00000000000000000000000000000001"))
        let c = try #require(HexToken("10000000000000000000000000000000"))
        #expect(a.matches(b))
        #expect(!a.matches(c))
    }
}
