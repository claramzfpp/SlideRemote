//
//  ContentView.swift
//  SlideRemote
//
//  Created by Clara Muniz on 18/09/25.
//

import SwiftUI

/// Mesmo app nos dois aparelhos: o iPad mostra os slides, o iPhone envia as setas.
struct ContentView: View {
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            PresentationView()
        } else {
            RemoteView()
        }
    }
}

#Preview {
    ContentView()
}
