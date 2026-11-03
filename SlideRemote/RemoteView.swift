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
    @State private var isDebugProcess: Bool = false
    
    var body: some View {
        VStack {
            iPadInfo
            
            Spacer()
                        
            iphoneControlButtons
            
            Spacer()
            
            if isDebugProcess {
                watchInfo
            }
        }
        .background(Color.gray.opacity(0.2))
        .onAppear {
            // Cada movimento detectado no Watch aumenta o contador do iPad.
            connectivity.onMovementReceived = { iPmanager.sendNextSlideCommand() }
        }
        .onDisappear { connectivity.onMovementReceived = nil }
    }
    
    private var iphoneControlButtons: some View {
        HStack {
            ArrowButton(
                image: Image(systemName: "arrow.left"),
                accessibilityLabel: "Slide Anterior"
            ) {
                iPmanager.sendPreviousSlideCommand()
            }
            
            Spacer()
            
            ArrowButton(
                image: Image(systemName: "arrow.right"),
                accessibilityLabel: "Próximo Slide"
            ) {
                iPmanager.sendNextSlideCommand()
            }

        }
        .disabled(!iPmanager.isConnected)
        .padding(.horizontal, 30)
        .padding(.vertical)
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

struct ArrowButton: View {
    var image: Image
    var accessibilityLabel: String
    var action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            image
                .resizable()
                .frame(width: 80, height: 80)
                .padding(24)
                .foregroundColor(.white)
                .background {
                    Circle()
                }
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    RemoteView()
}

#Preview {
    ArrowButton(
        image: Image(systemName: "arrow.left"),
        accessibilityLabel: "Slide Anterior"
    ) {
        print("pra trás")
    }
}

