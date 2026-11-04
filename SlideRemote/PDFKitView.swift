//
//  PDFKitView.swift
//  SlideRemote
//
//  Mostra uma página do PDF por vez. Quem muda de página é o controle remoto.
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
        // O toque do usuário não deve rolar o slide: só o remoto controla.
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
