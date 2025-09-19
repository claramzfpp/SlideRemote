//
//  WatchConnectivityManager.swift
//  RotateWritsDetection
//
//  Created by Clara Muniz on 18/09/25.
//

import WatchConnectivity
import Foundation

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var receivedMovement: String = "Waiting for Watch data..."
    @Published var isWatchConnected: Bool = false
    @Published var lastMovementData: [String: Any] = [:]
    
    override init() {
        super.init()
        
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func sendMovementData(_ movement: String, acceleration: [String: Double], location: String) {
        guard WCSession.default.isReachable else { return }
        
        let data: [String: Any] = [
            "movement": movement,
            "acceleration": acceleration,
            "location": location,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        WCSession.default.sendMessage(data, replyHandler: nil) { error in
            print("Error sending data: \(error.localizedDescription)")
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchConnected = activationState == .activated
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            self.lastMovementData = message
            
            if let movement = message["movement"] as? String,
               let location = message["location"] as? String {
                self.receivedMovement = "\(movement) detected at \(location)"
            }
        }
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
