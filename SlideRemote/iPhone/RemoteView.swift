//
//  RemoteView.swift
//  SlideRemote
//
//  Tela do iPhone: setas que controlam o contador do iPad.
//

import SwiftUI

struct RemoteView: View {
    @StateObject private var viewModel = RemoteViewModel(
        sender: MultipeerRemoteSender(),
        movementSource: WatchConnectivityManager.shared
    )
    
    var body: some View {
        VStack {
            iPadInfo
            
            Spacer()
                        
            iphoneControlButtons
            
            Spacer()
        }
        .background(Color.gray.opacity(0.2))
        .onAppear { viewModel.startListeningToWatch() }
        .onDisappear { viewModel.stopListeningToWatch() }
    }
    
    private var iphoneControlButtons: some View {
        HStack {
            ArrowButton(
                image: Image(systemName: "arrow.left"),
                accessibilityLabel: "Slide Anterior"
            ) {
                viewModel.previous()
            }
            
            Spacer()
            
            ArrowButton(
                image: Image(systemName: "arrow.right"),
                accessibilityLabel: "Próximo Slide"
            ) {
                viewModel.next()
            }

        }
        .disabled(!viewModel.isConnected)
        .padding(.horizontal, 30)
        .padding(.vertical)
    }
    
    private var iPadInfo: some View {
        Label(
            viewModel.isConnected ? "iPad conectado" : "Procurando iPad...",
            systemImage: viewModel.isConnected ? "ipad" : "ipad.slash"
        )
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .foregroundStyle(viewModel.isConnected ? .green : .secondary)
        .padding(.top)
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

