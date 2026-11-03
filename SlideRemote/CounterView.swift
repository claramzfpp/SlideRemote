//
//  CounterView.swift
//  SlideRemote
//
//  Tela do iPad: mostra o contador controlado pelas setas do iPhone.
//

import SwiftUI

struct CounterView: View {
    @StateObject private var receiver = CounterReceiver()

    var body: some View {
        VStack(spacing: 24) {
            Text("Contador")
                .font(.title)

            Text("\(receiver.counter)")
                .font(.system(size: 120, weight: .bold))

            Label(
                receiver.isConnected ? "iPhone conectado" : "Aguardando iPhone...",
                systemImage: receiver.isConnected ? "iphone.radiowaves.left.and.right" : "iphone.slash"
            )
            .foregroundStyle(receiver.isConnected ? .green : .secondary)
        }
        .padding()
    }
}

#Preview {
    CounterView()
}
