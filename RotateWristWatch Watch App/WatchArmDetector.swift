//
//  WatchArmDetector.swift
//  RotateWritsDetection
//
//  Created by Clara Muniz on 18/09/25.
//

//https://gstvdfnbch.medium.com/gesture-detection-on-the-apple-watch-core-motion-7650a652e5b9

import CoreMotion
import WatchKit
import Foundation

enum MovementDirection: String, CaseIterable {
    case shake = "Shake"
    case none = "None"
}

class WatchArmDetector: NSObject, ObservableObject {
    private let motionManager = CMMotionManager()
    private let connectivityManager = WatchConnectivityManager.shared
    
    @Published var isActive: Bool = false
    @Published var currentDirection: MovementDirection = .none
    
    override init() {
        super.init()
    }
    
    func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data else { return }
            self.processWatchMotion(data)
        }
        
        isActive = true
    }
    
    func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
        isActive = false
    }
    
    private func processWatchMotion(_ motion: CMDeviceMotion) {
        let userAcceleration = motion.userAcceleration
        let attitude = motion.attitude
        
        let totalAcceleration = sqrt(
            userAcceleration.x * userAcceleration.x +
            userAcceleration.y * userAcceleration.y +
            userAcceleration.z * userAcceleration.z
        )
        
        var detectedDirection: MovementDirection = .none
        var movementDescription = ""
        
        // Detecta movimento de sacudir
        if totalAcceleration > 0.5 || abs(attitude.roll) > 0.5 {
            detectedDirection = .shake
            movementDescription = "Wrist SHAKING"
        }
        
        // Se detectou movimento, envia para iPhone
        if detectedDirection != .none && detectedDirection != currentDirection {
            currentDirection = detectedDirection
            
            DispatchQueue.main.async {
                
                // Vibração no watch
                WKInterfaceDevice.current().play(.success)
                
                // Envia dados para iPhone
                let accelerationData = [
                    "x": userAcceleration.x,
                    "y": userAcceleration.y,
                    "z": userAcceleration.z,
                    "total": totalAcceleration
                ]
                
                self.connectivityManager.sendMovementData(
                    movementDescription,
                    acceleration: accelerationData,
                    location: "Apple Watch on wrist"
                )
            }
            
            // Reset após 1 segundo para detectar novos movimentos
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.currentDirection = .none
            }
        }
    }
}
