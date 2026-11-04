//
//  Presentation.swift
//  SlideRemote
//
//  Estado de uma apresentação: slide atual e total, sempre dentro dos limites.
//

import Foundation

struct Presentation {
    let pageCount: Int
    private(set) var currentIndex = 0

    init(pageCount: Int) {
        self.pageCount = max(pageCount, 0)
    }

    /// Número do slide para exibir (começa em 1).
    var currentPage: Int { currentIndex + 1 }

    var isAtFirst: Bool { currentIndex == 0 }
    var isAtLast: Bool { currentIndex >= pageCount - 1 }

    mutating func next() {
        guard !isAtLast else { return }
        currentIndex += 1
    }

    mutating func previous() {
        guard !isAtFirst else { return }
        currentIndex -= 1
    }

    mutating func apply(_ command: RemoteCommand) {
        switch command {
        case .next: next()
        case .previous: previous()
        }
    }
}
