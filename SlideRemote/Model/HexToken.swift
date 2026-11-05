//
//  HexToken.swift
//  SlideRemote
//

import Foundation

/// 128 bits aleatórios em 32 caracteres hexadecimais minúsculos.
/// Serve de credencial de reconexão e de desafio (nonce).
struct HexToken: Equatable, Sendable {
    static let length = 32

    let value: String

    init?(_ value: String) {
        guard Self.isLowercaseHex(value, length: Self.length) else { return nil }
        self.value = value
    }

    static func generate() -> HexToken {
        var generator = SystemRandomNumberGenerator()
        let hex = (0..<length / 2).map { _ in
            String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator))
        }.joined()
        return HexToken(hex)!
    }

    func matches(_ other: HexToken) -> Bool {
        constantTimeEquals(value, other.value)
    }
}

func isLowercaseHex(_ string: String, length: Int) -> Bool {
    string.utf8.count == length && string.utf8.allSatisfy {
        ($0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9")) || ($0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "f"))
    }
}

/// Não para no primeiro byte diferente, para o tempo de resposta não revelar quantos bytes batem.
func constantTimeEquals(_ a: String, _ b: String) -> Bool {
    let lhs = Array(a.utf8), rhs = Array(b.utf8)
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
}

private extension HexToken {
    static func isLowercaseHex(_ string: String, length: Int) -> Bool {
        SlideRemote.isLowercaseHex(string, length: length)
    }
}
