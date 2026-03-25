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

    var startPositionY: Double?
    var bottomPositionY: Double?
    var eccentricDurationSeconds: Double?
    var bottomPauseDurationSeconds: Double?
    var concentricDurationSeconds: Double?
    var topPauseDurationSeconds: Double?
    var topLockoutCompleteness: Double?
    var hipAsymmetry: Double?
    var elbowFlareAngle: Double?
    var elbowSymmetry: Double?
    var forearmVerticality: Double?
    var torsoAngleToFloor: Double?
    var bodyLineStraightness: Double?
    var headAlignment: Double?
    var lateralDrift: Double?
    var centerOfMassDriftProxy: Double?
    var pathJerkiness: Double?
    var stickingPointPercent: Double?
    var wobbleEvents: Int?

    var session: PushupSession?

    init(
        repNumber: Int,
        durationSeconds: Double,
        depthScreenSpace: Double,
        depthWorldMeters: Double? = nil,
        shoulderAsymmetry: Double,
        shoulderAsymmetryWorld: Double? = nil,
        startPositionY: Double? = nil,
        bottomPositionY: Double? = nil,
        eccentricDurationSeconds: Double? = nil,
        bottomPauseDurationSeconds: Double? = nil,
        concentricDurationSeconds: Double? = nil,
        topPauseDurationSeconds: Double? = nil,
        topLockoutCompleteness: Double? = nil,
        hipAsymmetry: Double? = nil,
        elbowFlareAngle: Double? = nil,
        elbowSymmetry: Double? = nil,
        forearmVerticality: Double? = nil,
        torsoAngleToFloor: Double? = nil,
        bodyLineStraightness: Double? = nil,
        headAlignment: Double? = nil,
        lateralDrift: Double? = nil,
        centerOfMassDriftProxy: Double? = nil,
        pathJerkiness: Double? = nil,
        stickingPointPercent: Double? = nil,
        wobbleEvents: Int? = nil
    ) {
        self.repNumber = repNumber
        self.durationSeconds = durationSeconds
        self.depthScreenSpace = depthScreenSpace
        self.depthWorldMeters = depthWorldMeters
        self.shoulderAsymmetry = shoulderAsymmetry
        self.shoulderAsymmetryWorld = shoulderAsymmetryWorld
        self.startPositionY = startPositionY
        self.bottomPositionY = bottomPositionY
        self.eccentricDurationSeconds = eccentricDurationSeconds
        self.bottomPauseDurationSeconds = bottomPauseDurationSeconds
        self.concentricDurationSeconds = concentricDurationSeconds
        self.topPauseDurationSeconds = topPauseDurationSeconds
        self.topLockoutCompleteness = topLockoutCompleteness
        self.hipAsymmetry = hipAsymmetry
        self.elbowFlareAngle = elbowFlareAngle
        self.elbowSymmetry = elbowSymmetry
        self.forearmVerticality = forearmVerticality
        self.torsoAngleToFloor = torsoAngleToFloor
        self.bodyLineStraightness = bodyLineStraightness
        self.headAlignment = headAlignment
        self.lateralDrift = lateralDrift
        self.centerOfMassDriftProxy = centerOfMassDriftProxy
        self.pathJerkiness = pathJerkiness
        self.stickingPointPercent = stickingPointPercent
        self.wobbleEvents = wobbleEvents
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
            shoulderAsymmetryWorld: asymmetryWorld,
            startPositionY: Double(measurement.topPositionY),
            bottomPositionY: Double(measurement.bottomPositionY),
            eccentricDurationSeconds: measurement.eccentricDurationSeconds,
            bottomPauseDurationSeconds: measurement.bottomPauseDurationSeconds,
            concentricDurationSeconds: measurement.concentricDurationSeconds,
            topPauseDurationSeconds: measurement.topPauseDurationSeconds,
            topLockoutCompleteness: measurement.topLockoutCompleteness,
            hipAsymmetry: measurement.hipAsymmetry,
            elbowFlareAngle: measurement.elbowFlareAngle,
            elbowSymmetry: measurement.elbowSymmetry,
            forearmVerticality: measurement.forearmVerticality,
            torsoAngleToFloor: measurement.torsoAngleToFloor,
            bodyLineStraightness: measurement.bodyLineStraightness,
            headAlignment: measurement.headAlignment,
            lateralDrift: measurement.lateralDrift,
            centerOfMassDriftProxy: measurement.centerOfMassDriftProxy,
            pathJerkiness: measurement.pathJerkiness,
            stickingPointPercent: measurement.stickingPointPercent,
            wobbleEvents: measurement.wobbleEvents
        )
    }
}
