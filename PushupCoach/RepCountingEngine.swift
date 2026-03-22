import Foundation
import CoreGraphics

final class RepCountingEngine {
    enum Phase: String, Sendable {
        case idle = "Idle"
        case ready = "Ready"
        case down = "Down"
        case up = "Up"
        case paused = "Paused"
    }

    struct RepUpdate {
        let phase: Phase
        let repCount: Int
        let noseY: CGFloat?
        let depthPercent: CGFloat?
        let debugMessage: String?
    }

    private(set) var repCount: Int = 0
    private(set) var currentPhase: Phase = .idle

    private var baselineNoseY: CGFloat?
    private var baselineWorldY: Float?
    private var minNoseYThisRep: CGFloat = 1.0
    private var maxNoseYThisRep: CGFloat = 0.0
    private var minWorldYThisRep: Float = .greatestFiniteMagnitude
    private var maxWorldYThisRep: Float = -.greatestFiniteMagnitude

    private let framesRequired = 4
    private var framesInCandidate = 0
    private var candidatePhase: Phase?

    // Screen-space thresholds (fraction of nose Y travel from baseline).
    private let downThresholdFraction: CGFloat = 0.06
    private let upThresholdFraction: CGFloat = 0.03

    // World-coordinate thresholds (meters).
    private let worldDownThreshold: Float = 0.04
    private let worldUpThreshold: Float = 0.02

    private var framesWithoutPose = 0
    private let pauseFrameThreshold = 15
    private var phaseBeforePause: Phase = .idle
    private var readyPoseStreak = 0
    private let framesRequiredForReadyLock = 12

    /// Adaptive max expected travel — calibrated from first completed reps.
    private var maxExpectedTravel: CGFloat = 0.15
    private var maxExpectedWorldTravel: Float = 0.12
    private var calibrationLocked = false

    struct RepMeasurement {
        let minNoseY: CGFloat
        let maxNoseY: CGFloat
        let minWorldY: Float?
        let maxWorldY: Float?
        let durationSeconds: TimeInterval
        let leftShoulderYs: [CGFloat]
        let rightShoulderYs: [CGFloat]
        let leftShoulderWorldYs: [Float]
        let rightShoulderWorldYs: [Float]
    }

    private var currentRepStartTime: TimeInterval = 0
    private var leftShoulderYsThisRep: [CGFloat] = []
    private var rightShoulderYsThisRep: [CGFloat] = []
    private var leftShoulderWorldYsThisRep: [Float] = []
    private var rightShoulderWorldYsThisRep: [Float] = []
    private(set) var completedReps: [RepMeasurement] = []

    /// Whether we have world coordinates available this session.
    private var useWorldCoords = false

    func update(with pose: PoseResult?) -> RepUpdate {
        guard let pose else {
            return handlePoseLost()
        }
        guard pose.isRepCountingQualityPose else {
            return handlePoseLost()
        }

        framesWithoutPose = 0
        useWorldCoords = pose.worldLandmarks != nil

        if currentPhase == .paused {
            currentPhase = phaseBeforePause
            return RepUpdate(phase: currentPhase, repCount: repCount, noseY: nil, depthPercent: nil,
                             debugMessage: "Resumed tracking")
        }

        guard let nose = pose.landmark(.nose), nose.confidence > 0.5 else {
            return RepUpdate(phase: currentPhase, repCount: repCount, noseY: nil,
                             depthPercent: continuousDepthPercent(pose: pose), debugMessage: nil)
        }

        let noseY = nose.position.y
        let worldY = pose.worldLandmark(.nose)?.position.y

        collectShoulderData(from: pose)

        switch currentPhase {
        case .idle:
            return handleIdle(pose: pose, noseY: noseY, worldY: worldY)
        case .ready:
            return handleReady(noseY: noseY, worldY: worldY, timestamp: pose.timestamp)
        case .down:
            return handleDown(noseY: noseY, worldY: worldY, timestamp: pose.timestamp)
        case .up:
            return handleUp(noseY: noseY, worldY: worldY, timestamp: pose.timestamp)
        case .paused:
            return RepUpdate(phase: .paused, repCount: repCount, noseY: noseY,
                             depthPercent: continuousDepthPercent(pose: pose), debugMessage: nil)
        }
    }

    func reset() {
        repCount = 0
        currentPhase = .idle
        baselineNoseY = nil
        baselineWorldY = nil
        minNoseYThisRep = 1.0
        maxNoseYThisRep = 0.0
        minWorldYThisRep = .greatestFiniteMagnitude
        maxWorldYThisRep = -.greatestFiniteMagnitude
        framesInCandidate = 0
        candidatePhase = nil
        framesWithoutPose = 0
        readyPoseStreak = 0
        completedReps = []
        leftShoulderYsThisRep = []
        rightShoulderYsThisRep = []
        leftShoulderWorldYsThisRep = []
        rightShoulderWorldYsThisRep = []
        maxExpectedTravel = 0.15
        maxExpectedWorldTravel = 0.12
        calibrationLocked = false
        useWorldCoords = false
    }

    // MARK: - Continuous depth signal (computed every frame, every phase)

    func continuousDepthPercent(pose: PoseResult?) -> CGFloat {
        guard let pose else { return 0 }

        if useWorldCoords, let worldY = pose.worldLandmark(.nose)?.position.y, let baseW = baselineWorldY {
            let travel = worldY - baseW
            return CGFloat(min(max(travel / maxExpectedWorldTravel, 0), 1.0))
        }

        guard let nose = pose.landmark(.nose), nose.confidence > 0.3, let baseline = baselineNoseY else { return 0 }
        let travel = nose.position.y - baseline
        return min(max(travel / maxExpectedTravel, 0), 1.0)
    }

    // MARK: - Phase handlers

    private func handlePoseLost() -> RepUpdate {
        framesWithoutPose += 1
        readyPoseStreak = 0
        if framesWithoutPose >= pauseFrameThreshold && currentPhase != .paused && currentPhase != .idle {
            phaseBeforePause = currentPhase
            currentPhase = .paused
            return RepUpdate(phase: .paused, repCount: repCount, noseY: nil, depthPercent: nil,
                             debugMessage: "Body lost — paused")
        }
        return RepUpdate(phase: currentPhase, repCount: repCount, noseY: nil, depthPercent: nil, debugMessage: nil)
    }

    private func handleIdle(pose: PoseResult, noseY: CGFloat, worldY: Float?) -> RepUpdate {
        if pose.isPostureReadyForRepCounting {
            readyPoseStreak += 1
            if readyPoseStreak >= framesRequiredForReadyLock {
                baselineNoseY = noseY
                baselineWorldY = worldY
                currentPhase = .ready
                readyPoseStreak = 0
                return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0,
                                 debugMessage: "Start position locked — baseline noseY: \(String(format: "%.3f", noseY))")
            }
            return RepUpdate(
                phase: .idle,
                repCount: repCount,
                noseY: noseY,
                depthPercent: nil,
                debugMessage: "Hold plank to lock start position (\(readyPoseStreak)/\(framesRequiredForReadyLock))"
            )
        }
        readyPoseStreak = 0
        return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil,
                         debugMessage: "Waiting for landmarks, distance & plank angle")
    }

    private func handleReady(noseY: CGFloat, worldY: Float?, timestamp: TimeInterval) -> RepUpdate {
        guard let baseline = baselineNoseY else {
            currentPhase = .idle
            return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil, debugMessage: nil)
        }

        let isGoingDown: Bool
        if useWorldCoords, let wy = worldY, let bw = baselineWorldY {
            isGoingDown = (wy - bw) > worldDownThreshold
        } else {
            isGoingDown = (noseY - baseline) > downThresholdFraction
        }

        if isGoingDown {
            if confirmTransition(to: .down) {
                currentPhase = .down
                minNoseYThisRep = noseY
                maxNoseYThisRep = baseline
                minWorldYThisRep = worldY ?? .greatestFiniteMagnitude
                maxWorldYThisRep = baselineWorldY ?? -.greatestFiniteMagnitude
                currentRepStartTime = timestamp
                leftShoulderYsThisRep = []
                rightShoulderYsThisRep = []
                leftShoulderWorldYsThisRep = []
                rightShoulderWorldYsThisRep = []
                return RepUpdate(phase: .down, repCount: repCount, noseY: noseY,
                                 depthPercent: depthPercent(noseY, worldY: worldY),
                                 debugMessage: "Entering DOWN phase")
            }
        } else {
            resetCandidate()
        }

        return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: nil)
    }

    private func handleDown(noseY: CGFloat, worldY: Float?, timestamp: TimeInterval) -> RepUpdate {
        guard let baseline = baselineNoseY else {
            return RepUpdate(phase: currentPhase, repCount: repCount, noseY: noseY, depthPercent: nil, debugMessage: nil)
        }

        minNoseYThisRep = max(minNoseYThisRep, noseY)
        if let wy = worldY {
            minWorldYThisRep = min(minWorldYThisRep, wy)
            maxWorldYThisRep = max(maxWorldYThisRep, wy)
        }

        let isComingUp: Bool
        if useWorldCoords, let wy = worldY, let bw = baselineWorldY {
            let returnDelta = maxWorldYThisRep - wy
            isComingUp = returnDelta > worldUpThreshold && (wy - bw) < worldDownThreshold
        } else {
            let returnDelta = minNoseYThisRep - noseY
            isComingUp = returnDelta > upThresholdFraction && (noseY - baseline) < downThresholdFraction
        }

        if isComingUp {
            if confirmTransition(to: .up) {
                currentPhase = .up
                let measurement = RepMeasurement(
                    minNoseY: minNoseYThisRep,
                    maxNoseY: maxNoseYThisRep,
                    minWorldY: minWorldYThisRep == .greatestFiniteMagnitude ? nil : minWorldYThisRep,
                    maxWorldY: maxWorldYThisRep == -.greatestFiniteMagnitude ? nil : maxWorldYThisRep,
                    durationSeconds: timestamp - currentRepStartTime,
                    leftShoulderYs: leftShoulderYsThisRep,
                    rightShoulderYs: rightShoulderYsThisRep,
                    leftShoulderWorldYs: leftShoulderWorldYsThisRep,
                    rightShoulderWorldYs: rightShoulderWorldYsThisRep
                )
                completedReps.append(measurement)
                repCount += 1

                calibrateIfNeeded()

                minNoseYThisRep = 1.0
                maxNoseYThisRep = 0.0
                minWorldYThisRep = .greatestFiniteMagnitude
                maxWorldYThisRep = -.greatestFiniteMagnitude
                baselineNoseY = noseY
                baselineWorldY = worldY

                currentPhase = .ready
                return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0,
                                 debugMessage: "REP #\(repCount) counted! Duration: \(String(format: "%.2fs", measurement.durationSeconds))")
            }
        } else {
            resetCandidate()
        }

        return RepUpdate(phase: .down, repCount: repCount, noseY: noseY,
                         depthPercent: depthPercent(noseY, worldY: worldY), debugMessage: nil)
    }

    private func handleUp(noseY: CGFloat, worldY: Float?, timestamp: TimeInterval) -> RepUpdate {
        currentPhase = .ready
        return handleReady(noseY: noseY, worldY: worldY, timestamp: timestamp)
    }

    // MARK: - Adaptive calibration

    private func calibrateIfNeeded() {
        guard !calibrationLocked, completedReps.count >= 2 else { return }

        let screenDepths = completedReps.map { $0.minNoseY - $0.maxNoseY }
        let avgScreen = screenDepths.reduce(CGFloat(0), +) / CGFloat(screenDepths.count)
        maxExpectedTravel = max(0.05, min(0.4, avgScreen * 1.15))

        let worldDepths = completedReps.compactMap { rep -> Float? in
            guard let minW = rep.minWorldY, let maxW = rep.maxWorldY else { return nil }
            return maxW - minW
        }
        if !worldDepths.isEmpty {
            let avgWorld = worldDepths.reduce(Float(0), +) / Float(worldDepths.count)
            maxExpectedWorldTravel = max(0.03, min(0.3, avgWorld * 1.15))
        }

        if completedReps.count >= 3 {
            calibrationLocked = true
        }
    }

    // MARK: - Helpers

    private func confirmTransition(to phase: Phase) -> Bool {
        if candidatePhase == phase {
            framesInCandidate += 1
        } else {
            candidatePhase = phase
            framesInCandidate = 1
        }
        if framesInCandidate >= framesRequired {
            resetCandidate()
            return true
        }
        return false
    }

    private func resetCandidate() {
        candidatePhase = nil
        framesInCandidate = 0
    }

    private func depthPercent(_ noseY: CGFloat, worldY: Float?) -> CGFloat {
        if useWorldCoords, let wy = worldY, let bw = baselineWorldY {
            let travel = wy - bw
            return CGFloat(min(max(travel / maxExpectedWorldTravel, 0), 1.0))
        }
        guard let baseline = baselineNoseY else { return 0 }
        let travel = noseY - baseline
        return min(max(travel / maxExpectedTravel, 0), 1.0)
    }

    private func collectShoulderData(from pose: PoseResult) {
        if let left = pose.landmark(.leftShoulder), left.confidence > 0.5 {
            leftShoulderYsThisRep.append(left.position.y)
        }
        if let right = pose.landmark(.rightShoulder), right.confidence > 0.5 {
            rightShoulderYsThisRep.append(right.position.y)
        }
        if let wl = pose.worldLandmark(.leftShoulder), wl.confidence > 0.5 {
            leftShoulderWorldYsThisRep.append(wl.position.y)
        }
        if let wr = pose.worldLandmark(.rightShoulder), wr.confidence > 0.5 {
            rightShoulderWorldYsThisRep.append(wr.position.y)
        }
    }
}
