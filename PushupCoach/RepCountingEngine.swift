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

    // Calibration baseline captured when the user is in "up" (top) position.
    private var baselineNoseY: CGFloat?
    private var minNoseYThisRep: CGFloat = 1.0
    private var maxNoseYThisRep: CGFloat = 0.0

    // Smoothing: require N consecutive frames past threshold.
    private let framesRequired = 4
    private var framesInCandidate = 0
    private var candidatePhase: Phase?

    // Thresholds (fraction of nose Y travel from baseline).
    // "Down" = nose moves DOWN on screen = Y increases (top-left origin).
    private let downThresholdFraction: CGFloat = 0.06
    private let upThresholdFraction: CGFloat = 0.03

    // Pause detection.
    private var framesWithoutPose = 0
    private let pauseFrameThreshold = 8
    private var phaseBeforePause: Phase = .idle

    // Per-rep data for form scoring.
    struct RepMeasurement {
        let minNoseY: CGFloat
        let maxNoseY: CGFloat
        let durationSeconds: TimeInterval
        let leftShoulderYs: [CGFloat]
        let rightShoulderYs: [CGFloat]
    }

    private var currentRepStartTime: TimeInterval = 0
    private var leftShoulderYsThisRep: [CGFloat] = []
    private var rightShoulderYsThisRep: [CGFloat] = []
    private(set) var completedReps: [RepMeasurement] = []

    func update(with pose: PoseResult?) -> RepUpdate {
        guard let pose, pose.isBodyDetected else {
            return handlePoseLost()
        }

        framesWithoutPose = 0

        if currentPhase == .paused {
            currentPhase = phaseBeforePause
            return RepUpdate(phase: currentPhase, repCount: repCount, noseY: nil, depthPercent: nil,
                             debugMessage: "Resumed tracking")
        }

        guard let nose = pose.landmark(.nose), nose.confidence > 0.5 else {
            return RepUpdate(phase: currentPhase, repCount: repCount, noseY: nil, depthPercent: nil, debugMessage: nil)
        }

        let noseY = nose.position.y

        collectShoulderData(from: pose)

        switch currentPhase {
        case .idle:
            return handleIdle(pose: pose, noseY: noseY)
        case .ready:
            return handleReady(noseY: noseY, timestamp: pose.timestamp)
        case .down:
            return handleDown(noseY: noseY, timestamp: pose.timestamp)
        case .up:
            return handleUp(noseY: noseY, timestamp: pose.timestamp)
        case .paused:
            return RepUpdate(phase: .paused, repCount: repCount, noseY: noseY, depthPercent: nil, debugMessage: nil)
        }
    }

    func reset() {
        repCount = 0
        currentPhase = .idle
        baselineNoseY = nil
        minNoseYThisRep = 1.0
        maxNoseYThisRep = 0.0
        framesInCandidate = 0
        candidatePhase = nil
        framesWithoutPose = 0
        completedReps = []
        leftShoulderYsThisRep = []
        rightShoulderYsThisRep = []
    }

    // MARK: - Phase handlers

    private func handlePoseLost() -> RepUpdate {
        framesWithoutPose += 1
        if framesWithoutPose >= pauseFrameThreshold && currentPhase != .paused && currentPhase != .idle {
            phaseBeforePause = currentPhase
            currentPhase = .paused
            return RepUpdate(phase: .paused, repCount: repCount, noseY: nil, depthPercent: nil,
                             debugMessage: "Body lost — paused")
        }
        return RepUpdate(phase: currentPhase, repCount: repCount, noseY: nil, depthPercent: nil, debugMessage: nil)
    }

    private func handleIdle(pose: PoseResult, noseY: CGFloat) -> RepUpdate {
        if pose.areKeyLandmarksVisible && pose.isDistanceOK {
            baselineNoseY = noseY
            currentPhase = .ready
            return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0,
                             debugMessage: "Calibrated — baseline noseY: \(String(format: "%.3f", noseY))")
        }
        return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil,
                         debugMessage: "Waiting for landmarks & distance")
    }

    private func handleReady(noseY: CGFloat, timestamp: TimeInterval) -> RepUpdate {
        guard let baseline = baselineNoseY else {
            currentPhase = .idle
            return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil, debugMessage: nil)
        }

        let delta = noseY - baseline
        if delta > downThresholdFraction {
            if confirmTransition(to: .down) {
                currentPhase = .down
                minNoseYThisRep = noseY
                maxNoseYThisRep = baseline
                currentRepStartTime = timestamp
                leftShoulderYsThisRep = []
                rightShoulderYsThisRep = []
                return RepUpdate(phase: .down, repCount: repCount, noseY: noseY, depthPercent: depthPercent(noseY),
                                 debugMessage: "Entering DOWN phase, delta: \(String(format: "%.3f", delta))")
            }
        } else {
            resetCandidate()
        }

        return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: nil)
    }

    private func handleDown(noseY: CGFloat, timestamp: TimeInterval) -> RepUpdate {
        guard let baseline = baselineNoseY else { return RepUpdate(phase: currentPhase, repCount: repCount, noseY: noseY, depthPercent: nil, debugMessage: nil) }

        minNoseYThisRep = max(minNoseYThisRep, noseY)

        let returnDelta = minNoseYThisRep - noseY
        if returnDelta > upThresholdFraction && (noseY - baseline) < downThresholdFraction {
            if confirmTransition(to: .up) {
                currentPhase = .up
                let measurement = RepMeasurement(
                    minNoseY: minNoseYThisRep,
                    maxNoseY: maxNoseYThisRep,
                    durationSeconds: timestamp - currentRepStartTime,
                    leftShoulderYs: leftShoulderYsThisRep,
                    rightShoulderYs: rightShoulderYsThisRep
                )
                completedReps.append(measurement)
                repCount += 1

                minNoseYThisRep = 1.0
                maxNoseYThisRep = 0.0
                baselineNoseY = noseY

                currentPhase = .ready
                return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0,
                                 debugMessage: "REP #\(repCount) counted! Duration: \(String(format: "%.2fs", measurement.durationSeconds))")
            }
        } else {
            resetCandidate()
        }

        return RepUpdate(phase: .down, repCount: repCount, noseY: noseY, depthPercent: depthPercent(noseY),
                         debugMessage: nil)
    }

    private func handleUp(noseY: CGFloat, timestamp: TimeInterval) -> RepUpdate {
        currentPhase = .ready
        return handleReady(noseY: noseY, timestamp: timestamp)
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

    private func depthPercent(_ noseY: CGFloat) -> CGFloat {
        guard let baseline = baselineNoseY else { return 0 }
        let travel = noseY - baseline
        let maxExpectedTravel: CGFloat = 0.15
        return min(max(travel / maxExpectedTravel, 0), 1.0)
    }

    private func collectShoulderData(from pose: PoseResult) {
        if let left = pose.landmark(.leftShoulder), left.confidence > 0.5 {
            leftShoulderYsThisRep.append(left.position.y)
        }
        if let right = pose.landmark(.rightShoulder), right.confidence > 0.5 {
            rightShoulderYsThisRep.append(right.position.y)
        }
    }
}
