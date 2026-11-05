//
//  PairingCode.swift
//  SlideRemote
//

import Foundation

struct PairingCode: Equatable, Sendable {
    static let length = 6

    let value: String

    /// Falha se não forem exatamente 6 dígitos ASCII (0-9). Outros dígitos Unicode, sinais e espaços são recusados de propósito.
    init?(_ value: String) {
        guard value.utf8.count == Self.length,
              value.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) else { return nil }
        self.value = value
    }

    private static let upperBound = (0..<length).reduce(1) { acc, _ in acc * 10 }

    /// Aceita 0...999_999 e completa com zeros à esquerda.
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

    /// Compara sem parar no primeiro byte diferente, para não vazar quantos dígitos batem pelo tempo de resposta.
    func matches(_ other: PairingCode) -> Bool {
        zip(value.utf8, other.value.utf8).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
