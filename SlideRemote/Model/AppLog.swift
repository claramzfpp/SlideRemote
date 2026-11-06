//
//  AppLog.swift
//  SlideRemote
//
//  Logs do sistema (os.Logger) no lugar de print. Nomes de dispositivos costumam ser o
//  person's name, so they are always logged as `.private`; pairing codes are never logged.
//

import OSLog

enum AppLog {
    static let connectivity = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SlideRemote",
        category: "connectivity"
    )
}
