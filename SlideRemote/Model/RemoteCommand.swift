//
//  RemoteCommand.swift
//  SlideRemote
//
//  Commands the iPhone sends to the iPad. Shared by both sides.
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
