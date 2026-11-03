//
//  RemoteView.swift
//  SlideRemote
//
//  Tela do iPhone: setas que controlam o contador do iPad.
//

import SwiftUI

struct RemoteView: View {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @StateObject private var iPmanager = iPhoneManager()

    var body: some View {
        NavigationStack {
            VStack {
                Label(
                    iPmanager.isConnected ? "iPad conectado" : "Procurando iPad...",
                    systemImage: iPmanager.isConnected ? "ipad" : "ipad.slash"
                )
                .foregroundStyle(iPmanager.isConnected ? .green : .secondary)
                .padding(.top)

                HStack {
                    Button {
                        iPmanager.sendPreviousSlideCommand()
                    } label: {
                        Image(systemName: "arrow.left").font(.largeTitle)
                    }
                    .accessibilityLabel("Slide Anterior")

                    Spacer()

                    Button {
                        iPmanager.sendNextSlideCommand()
                    } label: {
                        Image(systemName: "arrow.right").font(.largeTitle)
                    }
                    .accessibilityLabel("Próximo Slide")
                }
                .disabled(!iPmanager.isConnected)
                .padding(.horizontal, 30)
                .padding(.vertical)

                List {
                    Section("Last Movement from Watch:") {
                        Text(connectivity.receivedMovement)

                        Text("\(connectivity.movimentCount) movements detected")
                    }

                    Button("Refresh") {
                        ///volta todos os dados do iphone pro estado inicial
                        connectivity.receivedMovement = "Waiting for Watch data..."
                        connectivity.movimentCount = 0
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color.gray.opacity(0.6))
            .navigationTitle("Slide Remote")
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarBackground(Color.gray.opacity(0.6), for: .navigationBar)
        }
    }
}

#Preview {
    RemoteView()
}
