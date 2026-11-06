//
//  Presentation.swift
//  SlideRemote
//
//  State of a presentation: current slide and total, always within bounds.
//

import Foundation

struct Presentation {
    let pageCount: Int
    private(set) var currentIndex = 0

    init(pageCount: Int) {
        self.pageCount = max(pageCount, 0)
    }

    /// Slide number to display (starts at 1).
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
