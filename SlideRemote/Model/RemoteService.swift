//
//  RemoteService.swift
//  SlideRemote
//
//  Identificador do serviço Multipeer, compartilhado por iPad e iPhone.
//

import Foundation

enum RemoteService {
    /// Precisa ser igual nos dois lados e bater com `NSBonjourServices` (`_number-sync._tcp`) no Info.plist.
    static let type = "number-sync"
}
