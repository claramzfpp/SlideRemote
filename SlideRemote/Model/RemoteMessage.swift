//
//  RemoteMessage.swift
//  SlideRemote
//
//  Tudo o que trafega entre iPhone e iPad. O formato é texto simples e fechado:
//  qualquer payload fora da lista é descartado.
//

import Foundation

enum RemoteMessage: Equatable, Sendable {
    case command(RemoteCommand)
    case pair(PairingCode)
    case pairingResult(PairingResult)

    private static let pairPrefix = "pair:"
    private static let resultPrefix = "pairing:"

    var data: Data { Data(wireString.utf8) }

    private var wireString: String {
        switch self {
        case .command(let command): command.rawValue
        case .pair(let code): Self.pairPrefix + code.value
        case .pairingResult(.accepted): Self.resultPrefix + "accepted"
        case .pairingResult(.locked): Self.resultPrefix + "locked"
        case .pairingResult(.rejected(let left)): Self.resultPrefix + "rejected:\(left)"
        }
    }

    init?(data: Data) {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }

        if let command = RemoteCommand(rawValue: raw) {
            self = .command(command)
        } else if raw.hasPrefix(Self.pairPrefix),
                  let code = PairingCode(String(raw.dropFirst(Self.pairPrefix.count))) {
            self = .pair(code)
        } else if raw.hasPrefix(Self.resultPrefix),
                  let result = Self.parseResult(String(raw.dropFirst(Self.resultPrefix.count))) {
            self = .pairingResult(result)
        } else {
            return nil
        }
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
