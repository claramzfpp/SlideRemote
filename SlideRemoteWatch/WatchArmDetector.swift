//
//  WatchArmDetector.swift
//  SlideRemote
//
//  Created by Clara Muniz on 18/09/25.
//

// https://gstvdfnbch.medium.com/gesture-detection-on-the-apple-watch-core-motion-7650a652e5b9

import CoreMotion
import WatchKit

class WatchArmDetector: NSObject, ObservableObject {
    private let motionManager = CMMotionManager()
    private let connectivityManager = WatchConnectivityManager.shared

    /// Values measured from the logs: the wrist twist shows up on the gyroscope's x axis
    /// (peaks of 4 to 14 rad/s, with ~99% of the rotation concentrated on that axis).
    /// Only the negative direction counts; the positive direction is the wrist returning.
    private static let twistThreshold = 4.0 // rad/s
    private static let minAxisDominance = 0.9
    private static let cooldown: TimeInterval = 1.0

    @Published var isActive: Bool = false
    private var isCoolingDown = false

    func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 0.02 // 50 Hz: quick wrist gestures last ~100-200 ms
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.processWatchMotion(data)
        }

        isActive = true
    }

    func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
        isActive = false
    }

    private func processWatchMotion(_ motion: CMDeviceMotion) {
        guard !isCoolingDown else { return }

        // Detects a wrist twist: fast rotation, almost entirely on the x axis
        let rate = motion.rotationRate
        let rotation = sqrt(rate.x * rate.x + rate.y * rate.y + rate.z * rate.z)
        let isWristTwist = rate.x < -Self.twistThreshold
            && abs(rate.x) / rotation >= Self.minAxisDominance

        guard isWristTwist else { return }

        isCoolingDown = true
        WKInterfaceDevice.current().play(.success)
        connectivityManager.sendMovement()

        // Avoids firing several times for the same gesture.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cooldown) { [weak self] in
            self?.isCoolingDown = false
        }
    }
}
