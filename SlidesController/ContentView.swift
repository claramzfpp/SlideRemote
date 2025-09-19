//
//  ContentView.swift
//  SlidesController
//
//  Created by Clara Muniz on 19/09/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var macManager = MacManager()

    var body: some View {
        VStack {
            Text("Número Atual:")
                .font(.title)
            Text("\(macManager.currentNumber)") // Exibe o número recebido
                .font(.system(size: 72, weight: .bold))
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
