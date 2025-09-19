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
        NavigationStack {
            List {
                Section("Last Movement from Watch:") {
                    Text(connectivity.receivedMovement)
                }
                
            }
            .scrollContentBackground(.hidden)
            .background(Color.gray.opacity(0.2))
            .navigationTitle("Motion Detector")
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarBackground(Color.gray.opacity(0.6), for: .navigationBar)
        }
    }
}


#Preview {
    ContentView()
}
