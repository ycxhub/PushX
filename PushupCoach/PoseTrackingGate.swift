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
    private let framesToLock = 6

    private var totalLossStreak = 0
    private let framesToDrop = 30

    private var weakConfidenceStreak = 0

    private var shoulderMidSamples: [CGFloat] = []
    private var hipMidSamples: [CGFloat] = []
    private var spanSamples: [CGFloat] = []
    private let stabilitySampleCap = 6
    private let shoulderStabilityMaxRange: CGFloat = 0.035
    private let hipStabilityMaxRange: CGFloat = 0.045
    private let spanStabilityMaxRange: CGFloat = 0.05

    func update(pose: PoseResult?, secondsSinceStartup: TimeInterval? = nil) -> PoseTrackingGateResult {
        switch currentState {
        case .lost, .liningUp:
            return handleBeforeLock(pose: pose, secondsSinceStartup: secondsSinceStartup)
        case .locked:
            return handleWhileLocked(pose: pose)
        }
    }

    // MARK: - Before lock

    private func handleBeforeLock(pose: PoseResult?, secondsSinceStartup: TimeInterval?) -> PoseTrackingGateResult {
        guard let pose, pose.hasAnybodyPresent else {
            resetLockProgress()
            currentState = .lost
            return PoseTrackingGateResult(state: .lost, poseForRepCounting: nil,
                                         coachingMessage: "Get back in frame — we can't see your body.")
        }

        let coreOK = pose.hasCoreLandmarksForTracking
        let spanOK = pose.hasShoulderSpanInTrackingBand

        if coreOK, spanOK {
            if let shoulderMidY = pose.shoulderMidYForTracking {
                shoulderMidSamples.append(shoulderMidY)
                if shoulderMidSamples.count > stabilitySampleCap {
                    shoulderMidSamples.removeFirst()
                }
            }
            if let hipMidY = pose.hipMidYForTracking {
                hipMidSamples.append(hipMidY)
                if hipMidSamples.count > stabilitySampleCap {
                    hipMidSamples.removeFirst()
                }
            }
            if let span = pose.shoulderSpanForCalibrationMetric {
                spanSamples.append(span)
                if spanSamples.count > stabilitySampleCap {
                    spanSamples.removeFirst()
                }
            }
        } else {
            resetLockProgress()
        }

        let startupGraceActive = (secondsSinceStartup ?? .greatestFiniteMagnitude) < 1.0
        let bodyStable: Bool = {
            let requiredSamples = startupGraceActive ? 3 : 4
            guard shoulderMidSamples.count >= requiredSamples, spanSamples.count >= requiredSamples else { return false }
            let shoulderStable = stabilityRange(shoulderMidSamples) < shoulderStabilityMaxRange
            let spanStable = stabilityRange(spanSamples) < spanStabilityMaxRange
            if hipMidSamples.count >= requiredSamples {
                return shoulderStable && spanStable && stabilityRange(hipMidSamples) < hipStabilityMaxRange
            }
            return shoulderStable && spanStable
        }()

        let readyForLock = coreOK && spanOK && bodyStable && (startupGraceActive || pose.isPushupLikeBodyOrientation)

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
        let message: String
        if !coreOK {
            switch pose.distanceAssessment {
            case .tooClose:
                message = "We can see you, but you're too close — move back slightly."
            case .tooFar:
                message = "We can see motion, but you're too far — come closer."
            case .unavailable, .usable, .ideal:
                message = "Upper body is only partly visible — bring shoulders and head into frame."
            }
        } else if !pose.isPushupLikeBodyOrientation {
            message = "Body visible, but not yet in pushup position."
        } else if !spanOK {
            switch pose.distanceAssessment {
            case .tooClose:
                message = "Visible and close enough to track, but too tight for stable counting — move back a bit."
            case .tooFar:
                message = "Visible and in position, but too far for stable counting — come closer."
            case .unavailable, .usable, .ideal:
                message = "Visible and in position — hold still while we lock on."
            }
        } else if pose.headReferenceY == nil {
            message = "Pushup position looks good — facial landmarks are marginal, but body tracking is stabilizing."
        } else {
            message = "Visible and almost ready — hold steady."
        }
        return PoseTrackingGateResult(state: .liningUp, poseForRepCounting: nil,
                                     coachingMessage: message)
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
        shoulderMidSamples.removeAll()
        hipMidSamples.removeAll()
        spanSamples.removeAll()
    }

    func reset() {
        currentState = .lost
        goodFrameStreak = 0
        totalLossStreak = 0
        weakConfidenceStreak = 0
        shoulderMidSamples.removeAll()
        hipMidSamples.removeAll()
        spanSamples.removeAll()
    }

    private func stabilityRange(_ values: [CGFloat]) -> CGFloat {
        guard let min = values.min(), let max = values.max() else { return .greatestFiniteMagnitude }
        return max - min
    }
}
