//
//  WatchConnectivityManager.swift
//  SlideRemote
//
//  Created by Clara Muniz on 18/09/25.
//

import WatchConnectivity /// manages communication between an iPhone app and an Apple Watch app
// Watch (gesto) → WatchConnectivityManager → iPhone → MultipeerRemoteSender (Multipeer) → iPad
import Foundation
import OSLog

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    private static let movementKey = "movement"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SlideRemoteWatch", category: "connectivity")

    /// Called on the iPhone for each movement received from the Watch.
    var onMovementReceived: (() -> Void)?

    override init() {
        super.init()

        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Watch → iPhone: signals that the gesture was detected. Only the event is sent, no sensor data.
    func sendMovement() {
        guard WCSession.default.isReachable else { return }

        WCSession.default.sendMessage([Self.movementKey: "wristTwist"], replyHandler: nil) { error in
            Self.log.error("Error sending data: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    /// iPhone: receives the event from the Watch.
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard message[Self.movementKey] is String else { return }
        DispatchQueue.main.async {
            self.onMovementReceived?()
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
