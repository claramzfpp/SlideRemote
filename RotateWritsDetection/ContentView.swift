//
//  ContentView.swift
//  RotateWritsDetection
//
//  Created by Clara Muniz on 18/09/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("iPhone - Watch Movement Receiver")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Status de conexão
            VStack(spacing: 10) {
                Text("Watch Connection:")
                    .font(.headline)
                
                Text(connectivity.isWatchConnected ? "🟢 Connected" : "🔴 Disconnected")
                    .font(.title2)
                    .foregroundColor(connectivity.isWatchConnected ? .green : .red)
            }
            
            // Último movimento recebido
            VStack(spacing: 10) {
                Text("Last Movement from Watch:")
                    .font(.headline)
                
                Text(connectivity.receivedMovement)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
            }
            
            // Dados detalhados
            if !connectivity.lastMovementData.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Movement Details:")
                        .font(.headline)
                    
                    if let acceleration = connectivity.lastMovementData["acceleration"] as? [String: Double] {
                        Text("X: \(String(format: "%.2f", acceleration["x"] ?? 0))")
                        Text("Y: \(String(format: "%.2f", acceleration["y"] ?? 0))")
                        Text("Z: \(String(format: "%.2f", acceleration["z"] ?? 0))")
                        Text("Total: \(String(format: "%.2f", acceleration["total"] ?? 0))")
                    }
                    
                    if let timestamp = connectivity.lastMovementData["timestamp"] as? TimeInterval {
                        Text("Time: \(Date(timeIntervalSince1970: timestamp).formatted())")
                    }
                }
                .font(.caption)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
            
            Text("Instructions:")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 5) {
                Text("1. Start detection on your Apple Watch")
                Text("2. Move your arm in different directions")
                Text("3. Watch the iPhone receive movement data")
                Text("4. Shake your wrist for shake detection")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
    }
}


#Preview {
    ContentView()
}
