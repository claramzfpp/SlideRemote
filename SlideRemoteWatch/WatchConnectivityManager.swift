//
//  WatchConnectivityManager.swift
//  SlideRemote
//
//  Created by Clara Muniz on 18/09/25.
//

import WatchConnectivity ///gerenciar a comunicação entre um aplicativo de iPhone e um aplicativo de Apple Watch
// Watch (gesto) → WatchConnectivityManager → iPhone → iPhoneManager (Multipeer) → iPad
import Foundation

class WatchConnectivityManager: NSObject, ObservableObject { ///isso daqui é tudo que o watch ENVIA pro iphone
    static let shared = WatchConnectivityManager()
    
    @Published var receivedMovement: String = "Waiting for Watch data..."
    @Published var isWatchConnected: Bool = false
    @Published var lastMovementData: [String: Any] = [:]
    @Published var movimentCount: Int = 0

    /// Chamado no iPhone a cada movimento recebido do Watch.
    var onMovementReceived: (() -> Void)?

    override init() {
        super.init()
        
        if WCSession.isSupported() { // garante que tudo está configurado corretamente para rodar o aplicativo
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func sendMovementData(_ movement: String, acceleration: [String: Double], location: String) { ///envia as informações do Watch pro iPhone
        guard WCSession.default.isReachable else { return }
        
        movimentCount += 1
        
        let data: [String: Any] = [
            "movement": movement,
            "acceleration": acceleration,
            "location": location,
            "timestamp": Date().timeIntervalSince1970,
            "movimentCount": movimentCount
        ]
        
        WCSession.default.sendMessage(data, replyHandler: nil) { error in
            print("Error sending data: \(error.localizedDescription)")
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate { ///como o iphone RECEBE os dados do watch
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchConnected = activationState == .activated
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            self.lastMovementData = message
            
            if let movement = message["movement"] as? String,
               let location = message["location"] as? String,
               let count = message["movimentCount"] as? Int
            {
                self.receivedMovement = "\(movement) detected at \(location)"
                self.movimentCount = count
                self.onMovementReceived?()
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
