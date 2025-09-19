//
//  ContentView.swift
//  RotateWristWatch Watch App
//
//  Created by Clara Muniz on 18/09/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var armDetector = WatchArmDetector()
    @StateObject private var connectivity = WatchConnectivityManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            title
            
            status

            button
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(Color.gray.opacity(0.2))
    }
    
    private var title: some View {
        Text("Motion Detector")
            .font(.title3)
            .bold()
    }
    
    private var status: some View {
        HStack {
            Text("Status:").font(.caption).bold()
            Text(armDetector.isActive ? "Detecting" : "Not detecting").font(.caption)
        }
    }
    
    private var button: some View {
        Button {
            if armDetector.isActive {
                armDetector.stopMotionUpdates()
            } else {
                armDetector.startMotionUpdates()
            }
        } label: {
            Text(armDetector.isActive ? "Stop" : "Start")
        }
        .foregroundStyle(armDetector.isActive ? .red : .green)
    }
    
    private var buttonView: some View {
        Circle()
            
    }
}

#Preview {
    ContentView()
}
