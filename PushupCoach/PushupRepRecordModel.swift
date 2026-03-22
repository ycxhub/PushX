import Foundation
import SwiftData

@Model
final class PushupRepRecord {
    var repNumber: Int
    var durationSeconds: Double

    /// Nose travel in normalized screen-space (minNoseY − maxNoseY).
    var depthScreenSpace: Double

    /// Nose travel in meters (world coords). Nil when Apple Vision is the provider.
    var depthWorldMeters: Double?

    /// Average |leftShoulderY − rightShoulderY| across paired per-frame samples (screen-space).
    var shoulderAsymmetry: Double

    /// Same metric in world coordinates (meters). Nil when Apple Vision is the provider.
    var shoulderAsymmetryWorld: Double?

    var session: PushupSession?

    init(
        repNumber: Int,
        durationSeconds: Double,
        depthScreenSpace: Double,
        depthWorldMeters: Double? = nil,
        shoulderAsymmetry: Double,
        shoulderAsymmetryWorld: Double? = nil
    ) {
        self.repNumber = repNumber
        self.durationSeconds = durationSeconds
        self.depthScreenSpace = depthScreenSpace
        self.depthWorldMeters = depthWorldMeters
        self.shoulderAsymmetry = shoulderAsymmetry
        self.shoulderAsymmetryWorld = shoulderAsymmetryWorld
    }

    /// Create a compact record from the engine's per-frame measurement.
    convenience init(from measurement: RepCountingEngine.RepMeasurement, repNumber: Int) {
        let depthScreen = Double(measurement.minNoseY - measurement.maxNoseY)

        let depthWorld: Double?
        if let minW = measurement.minWorldY, let maxW = measurement.maxWorldY {
            depthWorld = Double(maxW - minW)
        } else {
            depthWorld = nil
        }

        let pairCount = min(measurement.leftShoulderYs.count, measurement.rightShoulderYs.count)
        let asymmetry: Double
        if pairCount > 0 {
            var total = 0.0
            for i in 0..<pairCount {
                total += Double(abs(measurement.leftShoulderYs[i] - measurement.rightShoulderYs[i]))
            }
            asymmetry = total / Double(pairCount)
        } else {
            asymmetry = 0.0
        }

        let worldPairCount = min(measurement.leftShoulderWorldYs.count, measurement.rightShoulderWorldYs.count)
        let asymmetryWorld: Double?
        if worldPairCount > 0 {
            var total: Double = 0
            for i in 0..<worldPairCount {
                total += Double(abs(measurement.leftShoulderWorldYs[i] - measurement.rightShoulderWorldYs[i]))
            }
            asymmetryWorld = total / Double(worldPairCount)
        } else {
            asymmetryWorld = nil
        }

        self.init(
            repNumber: repNumber,
            durationSeconds: measurement.durationSeconds,
            depthScreenSpace: depthScreen,
            depthWorldMeters: depthWorld,
            shoulderAsymmetry: asymmetry,
            shoulderAsymmetryWorld: asymmetryWorld
        )
    }
}
