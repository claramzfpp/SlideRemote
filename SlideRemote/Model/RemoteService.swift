//
//  RemoteService.swift
//  SlideRemote
//
//  Multipeer service identifier, shared by iPad and iPhone.
//

import Foundation

enum RemoteService {
    /// Must be identical on both sides and match `NSBonjourServices` (`_number-sync._tcp`) no Info.plist.
    static let type = "number-sync"
}
