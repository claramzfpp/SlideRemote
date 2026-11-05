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

    @Test func generatedCodeIsAlwaysSixDigitsWithLeadingZeros() {
        var generator = FixedGenerator(value: 42)
        let code = PairingCode.generate(using: &generator)
        #expect(code.value == "000042")
    }

    @Test func generatedCodeStaysWithinRange() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            #expect(PairingCode(PairingCode.generate(using: &generator).value) != nil)
        }
    }
}

/// Gerador determinístico: `random(in:)` devolve sempre o resto de `value` dentro do intervalo.
private struct FixedGenerator: RandomNumberGenerator {
    let value: UInt64
    mutating func next() -> UInt64 { value }
}
