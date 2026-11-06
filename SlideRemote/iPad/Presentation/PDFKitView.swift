//
//  PDFKitView.swift
//  SlideRemote
//
//  Shows one PDF page at a time. The remote control is what changes pages.
//

import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let pageIndex: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.autoScales = true
        view.backgroundColor = .black
        // The user's touch must not scroll the slide: only the remote controls it.
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
        if let page = document.page(at: pageIndex), view.currentPage !== page {
            view.go(to: page)
        }
    }
}
