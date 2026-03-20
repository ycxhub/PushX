import Foundation

enum PoseTrackingState: Equatable {
    case lost
    case liningUp
    case locked
}

struct PoseTrackingGateResult {
    let state: PoseTrackingState
    let poseForRepCounting: PoseResult?
    let coachingMessage: String
}

/// Two-regime tracking gate:
///   - Before first lock: stable frames with core landmarks, shoulder span in band, and low nose motion.
///   - After lock: stay locked through confidence dips; only drop after `framesToDrop` consecutive
///     frames with NO usable observation at all.
final class PoseTrackingGate {
    private(set) var currentState: PoseTrackingState = .lost

    private var goodFrameStreak = 0
    private let framesToLock = 10

    private var totalLossStreak = 0
    private let framesToDrop = 30

    private var weakConfidenceStreak = 0

    private var noseYSamples: [CGFloat] = []
    private let noseSampleCap = 6
    private let noseStabilityMaxRange: CGFloat = 0.03

    func update(pose: PoseResult?) -> PoseTrackingGateResult {
        switch currentState {
        case .lost, .liningUp:
            return handleBeforeLock(pose: pose)
        case .locked:
            return handleWhileLocked(pose: pose)
        }
    }

    // MARK: - Before lock

    private func handleBeforeLock(pose: PoseResult?) -> PoseTrackingGateResult {
        guard let pose, pose.hasAnybodyPresent else {
            resetLockProgress()
            currentState = .lost
            return PoseTrackingGateResult(state: .lost, poseForRepCounting: nil,
                                         coachingMessage: "Get back in frame — we can't see your body.")
        }

        let coreOK = pose.hasCoreLandmarksForTracking
        let spanOK = pose.hasShoulderSpanInTrackingBand

        if coreOK, spanOK, let nose = pose.landmark(.nose), nose.confidence >= 0.25 {
            noseYSamples.append(nose.position.y)
            if noseYSamples.count > noseSampleCap {
                noseYSamples.removeFirst()
            }
        } else {
            noseYSamples.removeAll()
        }

        let noseStable: Bool = {
            guard noseYSamples.count >= 5 else { return false }
            guard let lo = noseYSamples.min(), let hi = noseYSamples.max() else { return false }
            return (hi - lo) < noseStabilityMaxRange
        }()

        let readyForLock = coreOK && spanOK && noseStable

        if readyForLock {
            goodFrameStreak += 1
        } else {
            goodFrameStreak = 0
        }

        if goodFrameStreak >= framesToLock {
            currentState = .locked
            totalLossStreak = 0
            weakConfidenceStreak = 0
            return PoseTrackingGateResult(state: .locked, poseForRepCounting: pose, coachingMessage: "")
        }

        currentState = .liningUp
        return PoseTrackingGateResult(state: .liningUp, poseForRepCounting: nil,
                                     coachingMessage: "Hold still — we're locking on your pose.")
    }

    // MARK: - While locked (sticky)

    private func handleWhileLocked(pose: PoseResult?) -> PoseTrackingGateResult {
        guard let pose else {
            totalLossStreak += 1
            if totalLossStreak >= framesToDrop {
                currentState = .lost
                resetLockProgress()
                return PoseTrackingGateResult(state: .lost, poseForRepCounting: nil,
                                             coachingMessage: "Get back in frame — we lost your body.")
            }
            return PoseTrackingGateResult(state: .locked, poseForRepCounting: nil, coachingMessage: "Adjusting…")
        }

        totalLossStreak = 0

        if pose.hasCoreLandmarksForTracking {
            weakConfidenceStreak = 0
            return PoseTrackingGateResult(state: .locked, poseForRepCounting: pose, coachingMessage: "")
        }

        weakConfidenceStreak += 1
        if weakConfidenceStreak > 60 {
            currentState = .liningUp
            resetLockProgress()
            return PoseTrackingGateResult(state: .liningUp, poseForRepCounting: nil,
                                         coachingMessage: "Having trouble tracking — try moving the phone a bit further away.")
        }

        return PoseTrackingGateResult(state: .locked, poseForRepCounting: pose, coachingMessage: "")
    }

    private func resetLockProgress() {
        goodFrameStreak = 0
        noseYSamples.removeAll()
    }

    func reset() {
        currentState = .lost
        goodFrameStreak = 0
        totalLossStreak = 0
        weakConfidenceStreak = 0
        noseYSamples.removeAll()
    }
}
