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
        VStack {
            iPadInfo
            
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
            
            watchInfo
        }
        .background(Color.gray.opacity(0.2))
        .onAppear {
            // Cada movimento detectado no Watch aumenta o contador do iPad.
            connectivity.onMovementReceived = { iPmanager.sendNextSlideCommand() }
        }
        .onDisappear { connectivity.onMovementReceived = nil }
    }
    
    private var iPadInfo: some View {
        Label(
            iPmanager.isConnected ? "iPad conectado" : "Procurando iPad...",
            systemImage: iPmanager.isConnected ? "ipad" : "ipad.slash"
        )
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .foregroundStyle(iPmanager.isConnected ? .green : .secondary)
        .padding(.top)
    }
    
    private var watchInfo: some View {
        List {
            Section("Last Movement from Watch:") {
                Text(connectivity.receivedMovement)
                
                Text("\(connectivity.movimentCount) movements detected")
            }
            
        }
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    RemoteView()
}
