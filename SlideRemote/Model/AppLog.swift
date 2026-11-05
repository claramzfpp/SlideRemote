//
//  AppLog.swift
//  SlideRemote
//
//  Logs do sistema (os.Logger) no lugar de print. Nomes de dispositivos costumam ser o
//  nome da pessoa, então entram sempre como `.private`; códigos de pareamento nunca são logados.
//

import OSLog

enum AppLog {
    static let connectivity = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SlideRemote",
        category: "connectivity"
    )
}
