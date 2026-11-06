//
//  PairingCode.swift
//  SlideRemote
//

import Foundation

struct PairingCode: Equatable, Sendable {
    static let length = 6

    let value: String

    /// Fails unless it is exactly 6 ASCII digits (0-9). Other Unicode digits, signs and spaces are rejected on purpose.
    init?(_ value: String) {
        guard value.utf8.count == Self.length,
              value.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) else { return nil }
        self.value = value
    }

    private static let upperBound = (0..<length).reduce(1) { acc, _ in acc * 10 }

    /// Accepts 0...999_999 and pads with leading zeros.
    init?(number: Int) {
        guard (0..<Self.upperBound).contains(number) else { return nil }
        let digits = String(number)
        self.init(String(repeating: "0", count: Self.length - digits.count) + digits)
    }

    static func generate<G: RandomNumberGenerator>(using generator: inout G) -> PairingCode {
        PairingCode(number: Int.random(in: 0..<upperBound, using: &generator))!
    }

    static func generate() -> PairingCode {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    /// Compares without stopping at the first differing byte, so response time doesn't leak how many digits match.
    func matches(_ other: PairingCode) -> Bool {
        zip(value.utf8, other.value.utf8).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
