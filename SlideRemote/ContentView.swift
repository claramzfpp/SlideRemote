//
//  ContentView.swift
//  SlideRemote
//
//  Created by Clara Muniz on 18/09/25.
//

import SwiftUI

/// Mesmo app nos dois aparelhos: o iPad recebe e conta, o iPhone envia as setas.
struct ContentView: View {
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            CounterView()
        } else {
            RemoteView()
        }
    }
}

#Preview {
    ContentView()
}
