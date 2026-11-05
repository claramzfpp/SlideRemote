//
//  PairingCodeTests.swift
//  SlideRemoteTests
//

import Testing
@testable import SlideRemote

struct PairingCodeTests {
    @Test func acceptsExactlySixDigits() {
        #expect(PairingCode("123456")?.value == "123456")
        #expect(PairingCode("000000")?.value == "000000")
    }

    @Test(arguments: ["", "12345", "1234567", "12345a", "12 456", "١٢٣٤٥٦", "+12345", "123.56"])
    func rejectsInvalidFormats(_ input: String) {
        #expect(PairingCode(input) == nil)
    }

    @Test func equalCodesMatch() throws {
        let a = try #require(PairingCode("482913"))
        let b = try #require(PairingCode("482913"))
        #expect(a.matches(b))
    }

    @Test func differentCodesDoNotMatch() throws {
        let a = try #require(PairingCode("482913"))
        let b = try #require(PairingCode("482914"))
        #expect(!a.matches(b))
    }

    @Test func numberIsPaddedWithLeadingZeros() {
        #expect(PairingCode(number: 0)?.value == "000000")
        #expect(PairingCode(number: 42)?.value == "000042")
        #expect(PairingCode(number: 999_999)?.value == "999999")
    }

    @Test func numberOutOfRangeIsRejected() {
        #expect(PairingCode(number: -1) == nil)
        #expect(PairingCode(number: 1_000_000) == nil)
    }

    @Test func generatedCodeStaysWithinRange() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            #expect(PairingCode(PairingCode.generate(using: &generator).value) != nil)
        }
    }
}
