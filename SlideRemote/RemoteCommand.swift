//
//  RemoteCommand.swift
//  SlideRemote
//
//  Comandos que o iPhone envia ao iPad. Compartilhado pelos dois lados.
//

import Foundation

enum RemoteCommand: String {
    case next
    case previous

    var data: Data { Data(rawValue.utf8) }

    init?(data: Data) {
        guard let rawValue = String(data: data, encoding: .utf8) else { return nil }
        self.init(rawValue: rawValue)
    }
}
