//
//  WatchArmDetector.swift
//  RotateWritsDetection
//
//  Created by Clara Muniz on 18/09/25.
//

// https://gstvdfnbch.medium.com/gesture-detection-on-the-apple-watch-core-motion-7650a652e5b9

import CoreMotion
import WatchKit
import Foundation

enum MovementDirection: String, CaseIterable {
    case rotation = "Rotation"
    case none = "None"
}

class WatchArmDetector: NSObject, ObservableObject {
    private let motionManager = CMMotionManager()
    private let connectivityManager = WatchConnectivityManager.shared

    /// Valores medidos nos logs: o giro do pulso aparece no eixo x do giroscópio
    /// (picos de 4 a 14 rad/s, com ~99% da rotação concentrada nesse eixo).
    /// Só o sentido negativo conta; o sentido positivo é a volta do punho.
    private static let twistThreshold = 4.0 // rad/s
    private static let minAxisDominance = 0.9

    @Published var isActive: Bool = false
    @Published var currentDirection: MovementDirection = .none
    
    override init() {
        super.init()
    }
    
    func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 0.02 // 50 Hz: gestos rápidos de pulso duram ~100-200 ms
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

        let totalAcceleration = sqrt(
            userAcceleration.x * userAcceleration.x +
            userAcceleration.y * userAcceleration.y +
            userAcceleration.z * userAcceleration.z
        )
        
        var detectedDirection: MovementDirection = .none
        var movementDescription = ""
        
        // Detecta giro do pulso: rotação rápida e quase toda no eixo x
        let rate = motion.rotationRate
        let rotation = sqrt(rate.x * rate.x + rate.y * rate.y + rate.z * rate.z)
        let isWristTwist = rate.x < -Self.twistThreshold
            && abs(rate.x) / rotation >= Self.minAxisDominance

        if isWristTwist {
            detectedDirection = .rotation
            movementDescription = "Wrist ROTATION"
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
