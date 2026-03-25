import Foundation
import CoreGraphics

final class RepCountingEngine {
    enum Phase: String, Sendable {
        case idle = "Idle"
        case ready = "Ready"
        case down = "Down"
        case ascending = "Ascending"
        case paused = "Paused"
    }

    struct RepUpdate {
        let phase: Phase
        let repCount: Int
        let noseY: CGFloat?
        let depthPercent: CGFloat?
        let debugMessage: String?
    }

    struct RepMeasurement {
        let minNoseY: CGFloat
        let maxNoseY: CGFloat
        let minWorldY: Float?
        let maxWorldY: Float?
        let durationSeconds: TimeInterval
        let eccentricDurationSeconds: TimeInterval
        let bottomPauseDurationSeconds: TimeInterval
        var concentricDurationSeconds: TimeInterval
        var topPauseDurationSeconds: TimeInterval
        let topPositionY: CGFloat
        let bottomPositionY: CGFloat
        var topLockoutCompleteness: Double
        let leftShoulderYs: [CGFloat]
        let rightShoulderYs: [CGFloat]
        let leftShoulderWorldYs: [Float]
        let rightShoulderWorldYs: [Float]
        let hipAsymmetry: Double
        let elbowFlareAngle: Double?
        let elbowSymmetry: Double?
        let forearmVerticality: Double?
        let torsoAngleToFloor: Double?
        let bodyLineStraightness: Double?
        let headAlignment: Double?
        let lateralDrift: Double
        let centerOfMassDriftProxy: Double
        let pathJerkiness: Double?
        let stickingPointPercent: Double?
        let wobbleEvents: Int
    }

    struct DiagnosticsSnapshot {
        let rejectionCounts: [String: Int]
        let readyLocks: Int
        let bootstrapStarts: Int
        let motionWhileIdleEvents: Int
        let pauseEvents: Int
        let firstRepBootstrapped: Bool
    }

    private struct BootstrapSample {
        let timestamp: TimeInterval
        let referenceY: CGFloat
        let shoulderMidY: CGFloat?
        let hipMidY: CGFloat?
        let wristMidY: CGFloat?
    }

    private struct RepFrameSample {
        let timestamp: TimeInterval
        let referenceY: CGFloat
        let shoulderMidY: CGFloat?
        let hipMidY: CGFloat?
        let wristMidY: CGFloat?
        let shoulderMidX: CGFloat?
        let hipMidX: CGFloat?
        let torsoAngleToFloor: CGFloat?
        let bodyLineAngle: CGFloat?
        let headAlignmentAngle: CGFloat?
        let leftElbowFlare: CGFloat?
        let rightElbowFlare: CGFloat?
        let leftForearmVerticality: CGFloat?
        let rightForearmVerticality: CGFloat?
        let leftHipY: CGFloat?
        let rightHipY: CGFloat?
    }

    private(set) var repCount: Int = 0
    private(set) var currentPhase: Phase = .idle

    private var baselineNoseY: CGFloat?
    private var baselineWorldY: Float?
    private var baselineShoulderMidY: CGFloat?
    private var baselineWristMidY: CGFloat?
    private var baselineHipMidY: CGFloat?

    private var peakNoseY: CGFloat = 0.0
    private var peakShoulderMidY: CGFloat = 0.0
    private var minWorldYThisRep: Float = .greatestFiniteMagnitude
    private var maxWorldYThisRep: Float = -.greatestFiniteMagnitude

    private let framesRequired = 3
    private var framesInCandidate = 0
    private var candidatePhase: Phase?

    private let downThresholdFraction: CGFloat = 0.045
    private let upThresholdFraction: CGFloat = 0.05
    private let bootstrapDownThreshold: CGFloat = 0.06
    private let minimumRelativeGapForDescent: CGFloat = 0.0
    private let maxWristDrift: CGFloat = 0.10
    private let maxHipDrift: CGFloat = 0.15
    private let minimumDepthGate: CGFloat = 0.065
    private let minimumRepDuration: TimeInterval = 0.35
    private let maximumRepDuration: TimeInterval = 8.0
    private let stalledDownTimeoutSeconds: TimeInterval = 2.2

    private let returnToBaselineTolerance: CGFloat = 0.06
    private let shoulderReturnTolerance: CGFloat = 0.04
    private let ascendingConfirmFrames = 4
    private let ascendingTimeoutSeconds: TimeInterval = 5.0

    private var ascendingStartTime: TimeInterval = 0
    private var deepestTimestamp: TimeInterval = 0
    private var framesNearBaseline: Int = 0
    private var pendingMeasurement: RepMeasurement?

    private var framesWithoutPose = 0
    private let pauseFrameThreshold = 15
    private var phaseBeforePause: Phase = .idle
    private var readyPoseStreak = 0
    private let framesRequiredForReadyLock = 18

    private var framesSinceLastReadyDiag = 0
    private let readyDiagInterval = 45

    private var maxExpectedTravel: CGFloat = 0.15
    private var maxExpectedWorldTravel: Float = 0.12
    private var calibrationLocked = false

    private var currentRepStartTime: TimeInterval = 0
    private var lastRepCompletionTime: TimeInterval?
    private var lastDownProgressTimestamp: TimeInterval = 0
    private var leftShoulderYsThisRep: [CGFloat] = []
    private var rightShoulderYsThisRep: [CGFloat] = []
    private var leftShoulderWorldYsThisRep: [Float] = []
    private var rightShoulderWorldYsThisRep: [Float] = []
    private var repSamples: [RepFrameSample] = []
    private var ascendingSamples: [RepFrameSample] = []
    private var bootstrapSamples: [BootstrapSample] = []
    private(set) var completedReps: [RepMeasurement] = []

    private var useWorldCoords = false

    private var rejectionCounts: [String: Int] = [:]
    private var readyLocks = 0
    private var bootstrapStarts = 0
    private var motionWhileIdleEvents = 0
    private var pauseEvents = 0
    private var firstRepBootstrapped = false

    var diagnosticsSnapshot: DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            rejectionCounts: rejectionCounts,
            readyLocks: readyLocks,
            bootstrapStarts: bootstrapStarts,
            motionWhileIdleEvents: motionWhileIdleEvents,
            pauseEvents: pauseEvents,
            firstRepBootstrapped: firstRepBootstrapped
        )
    }

    func update(with pose: PoseResult?) -> RepUpdate {
        guard let pose else {
            return handlePoseLost()
        }
        guard pose.isRepCountingQualityPose else {
            if pose.hasRepCountingAnchorLandmarks && pose.isPushupLikeBodyOrientation {
                motionWhileIdleEvents += 1
            }
            return handlePoseLost()
        }

        framesWithoutPose = 0
        useWorldCoords = pose.worldLandmarks != nil

        if currentPhase == .paused {
            currentPhase = phaseBeforePause
            return RepUpdate(phase: currentPhase, repCount: repCount, noseY: nil, depthPercent: nil,
                             debugMessage: "Resumed tracking")
        }

        guard let referenceY = pose.headReferenceY else {
            return RepUpdate(phase: currentPhase, repCount: repCount, noseY: nil,
                             depthPercent: continuousDepthPercent(pose: pose), debugMessage: "Head landmarks marginal — using body-only tracking")
        }

        let worldY = pose.worldLandmark(.nose)?.position.y
        let shoulderMidY = computeShoulderMidY(from: pose)
        let hipMidY = computeHipMidY(from: pose)
        let wristMidY = computeWristMidY(from: pose)

        recordBootstrapSample(referenceY: referenceY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, timestamp: pose.timestamp)
        collectShoulderData(from: pose)

        switch currentPhase {
        case .idle:
            return handleIdle(pose: pose, noseY: referenceY, worldY: worldY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY)
        case .ready:
            return handleReady(pose: pose, noseY: referenceY, worldY: worldY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, timestamp: pose.timestamp)
        case .down:
            return handleDown(pose: pose, noseY: referenceY, worldY: worldY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, timestamp: pose.timestamp)
        case .ascending:
            return handleAscending(pose: pose, noseY: referenceY, worldY: worldY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, timestamp: pose.timestamp)
        case .paused:
            return RepUpdate(phase: .paused, repCount: repCount, noseY: referenceY,
                             depthPercent: continuousDepthPercent(pose: pose), debugMessage: nil)
        }
    }

    func reset() {
        repCount = 0
        currentPhase = .idle
        baselineNoseY = nil
        baselineWorldY = nil
        baselineShoulderMidY = nil
        baselineWristMidY = nil
        baselineHipMidY = nil
        peakNoseY = 0.0
        peakShoulderMidY = 0.0
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
        repSamples = []
        ascendingSamples = []
        bootstrapSamples = []
        maxExpectedTravel = 0.15
        maxExpectedWorldTravel = 0.12
        calibrationLocked = false
        useWorldCoords = false
        ascendingStartTime = 0
        deepestTimestamp = 0
        lastDownProgressTimestamp = 0
        framesNearBaseline = 0
        pendingMeasurement = nil
        framesSinceLastReadyDiag = 0
        lastRepCompletionTime = nil
        rejectionCounts = [:]
        readyLocks = 0
        bootstrapStarts = 0
        motionWhileIdleEvents = 0
        pauseEvents = 0
        firstRepBootstrapped = false
    }

    func continuousDepthPercent(pose: PoseResult?) -> CGFloat {
        guard let pose else { return 0 }

        if useWorldCoords, let worldY = pose.worldLandmark(.nose)?.position.y, let baseW = baselineWorldY {
            let travel = worldY - baseW
            return CGFloat(min(max(travel / maxExpectedWorldTravel, 0), 1.0))
        }

        guard let headY = pose.headReferenceY, let baseline = baselineNoseY else { return 0 }
        let travel = headY - baseline
        return min(max(travel / maxExpectedTravel, 0), 1.0)
    }

    private func handlePoseLost() -> RepUpdate {
        framesWithoutPose += 1
        readyPoseStreak = 0
        if framesWithoutPose >= pauseFrameThreshold && currentPhase != .paused && currentPhase != .idle {
            phaseBeforePause = currentPhase
            currentPhase = .paused
            pauseEvents += 1
            return RepUpdate(phase: .paused, repCount: repCount, noseY: nil, depthPercent: nil,
                             debugMessage: "Body lost — paused")
        }
        return RepUpdate(phase: currentPhase, repCount: repCount, noseY: nil, depthPercent: nil, debugMessage: nil)
    }

    private func handleIdle(pose: PoseResult, noseY: CGFloat, worldY: Float?, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?) -> RepUpdate {
        if pose.isPostureReadyForRepCounting {
            readyPoseStreak += 1
            if readyPoseStreak >= framesRequiredForReadyLock {
                lockBaseline(noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY)
                currentPhase = .ready
                readyPoseStreak = 0
                readyLocks += 1
                let msg = formatLockLog(noseY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY)
                return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: msg)
            }
            return RepUpdate(
                phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil,
                debugMessage: "Hold plank to lock start position (\(readyPoseStreak)/\(framesRequiredForReadyLock))"
            )
        }

        readyPoseStreak = 0

        if let bootstrap = bootstrapCandidate(currentY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY) {
            bootstrapStarts += 1
            if repCount == 0 {
                firstRepBootstrapped = true
            }
            lockBaseline(noseY: bootstrap.referenceY, worldY: nil, shoulderMidY: bootstrap.shoulderMidY, hipMidY: bootstrap.hipMidY, wristMidY: bootstrap.wristMidY)
            currentPhase = .down
            peakNoseY = noseY
            peakShoulderMidY = shoulderMidY ?? 0
            minWorldYThisRep = worldY ?? .greatestFiniteMagnitude
            maxWorldYThisRep = baselineWorldY ?? -.greatestFiniteMagnitude
            currentRepStartTime = bootstrap.timestamp
            deepestTimestamp = bootstrap.timestamp
            lastDownProgressTimestamp = bootstrap.timestamp
            repSamples = []
            ascendingSamples = []
            leftShoulderYsThisRep = []
            rightShoulderYsThisRep = []
            leftShoulderWorldYsThisRep = []
            rightShoulderWorldYsThisRep = []
            finalizePreviousRepTopPause(withStartTimestamp: bootstrap.timestamp)
            collectRepSample(from: pose, referenceY: noseY)
            return RepUpdate(
                phase: .down,
                repCount: repCount,
                noseY: noseY,
                depthPercent: depthPercent(noseY, worldY: worldY),
                debugMessage: "BOOTSTRAP DOWN | recovered from early motion before baseline lock"
            )
        }

        if pose.hasRepCountingAnchorLandmarks && pose.isPushupLikeBodyOrientation {
            motionWhileIdleEvents += 1
            return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil,
                             debugMessage: "Pushup-like motion detected, but baseline not stable yet")
        }

        if !pose.hasRepCountingAnchorLandmarks {
            return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil,
                             debugMessage: "Upper body partially visible — bring shoulders, arms, and hips into frame")
        }

        switch pose.distanceAssessment {
        case .tooFar:
            return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil,
                             debugMessage: "Distance too far — come closer so shoulders fill more of the frame")
        case .tooClose:
            return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil,
                             debugMessage: "Distance too close — move back slightly to fit your upper body")
        case .unavailable, .usable, .ideal:
            break
        }

        if pose.headReferenceY == nil {
            return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil,
                             debugMessage: "Head marginal — body visible, waiting for steadier upper-body landmarks")
        }

        return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil,
                         debugMessage: "Visible, but not yet in a stable pushup setup")
    }

    private func handleReady(pose: PoseResult, noseY: CGFloat, worldY: Float?, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, timestamp: TimeInterval) -> RepUpdate {
        guard let baseline = baselineNoseY else {
            currentPhase = .idle
            return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil, debugMessage: nil)
        }

        let noseDelta = noseY - baseline
        let noseDown = noseDelta > downThresholdFraction
        let shoulderDelta = (shoulderMidY != nil && baselineShoulderMidY != nil) ? shoulderMidY! - baselineShoulderMidY! : 0
        let shoulderDown = shoulderDelta > 0.025

        let relativeGap: CGFloat
        if let smY = shoulderMidY, let bsY = baselineShoulderMidY {
            relativeGap = noseDelta - (smY - bsY)
        } else {
            relativeGap = noseDelta
        }
        let relGatePass = relativeGap > minimumRelativeGapForDescent

        let wristDrift: CGFloat?
        if let wmY = wristMidY, let bwY = baselineWristMidY {
            wristDrift = abs(wmY - bwY)
        } else {
            wristDrift = nil
        }

        let hipDrift: CGFloat?
        if let hmY = hipMidY, let bhY = baselineHipMidY {
            hipDrift = abs(hmY - bhY)
        } else {
            hipDrift = nil
        }

        let extremeHipDrift = (hipDrift ?? 0) > maxHipDrift * 1.8
        let extremeWristDrift = (wristDrift ?? 0) > maxWristDrift * 1.8

        var descentScore = 0
        if noseDelta > 0.03 { descentScore += 1 }
        if noseDown { descentScore += 2 }
        if shoulderDown { descentScore += 2 }
        if relativeGap > minimumRelativeGapForDescent { descentScore += 2 }
        else if relativeGap > -0.05 { descentScore += 1 }
        if noseDelta > max(shoulderDelta + 0.01, 0.03) { descentScore += 1 }
        if shoulderDelta < noseDelta + 0.015 { descentScore += 1 }
        if let hipDrift, hipDrift <= maxHipDrift { descentScore += 1 }
        else if hipDrift == nil { descentScore += 1 }
        if let wristDrift, wristDrift <= maxWristDrift { descentScore += 1 }
        else if wristDrift == nil { descentScore += 1 }

        if let hipDrift, hipDrift > maxHipDrift { descentScore -= 1 }
        if let wristDrift, wristDrift > maxWristDrift { descentScore -= 1 }
        if relativeGap < -0.08 { descentScore -= 2 }

        let hasCoreDescentSignal =
            (noseDelta > 0.035 && (relativeGap > -0.06 || noseDelta > shoulderDelta + 0.02)) ||
            (shoulderDown && noseDelta > 0.025)
        let isGoingDown = hasCoreDescentSignal && descentScore >= 3 && !extremeHipDrift && !extremeWristDrift

        if isGoingDown {
            framesSinceLastReadyDiag = 0
            if confirmTransition(to: .down) {
                currentPhase = .down
                peakNoseY = noseY
                peakShoulderMidY = shoulderMidY ?? 0
                minWorldYThisRep = worldY ?? .greatestFiniteMagnitude
                maxWorldYThisRep = baselineWorldY ?? -.greatestFiniteMagnitude
                currentRepStartTime = timestamp
                deepestTimestamp = timestamp
                lastDownProgressTimestamp = timestamp
                repSamples = []
                ascendingSamples = []
                leftShoulderYsThisRep = []
                rightShoulderYsThisRep = []
                leftShoulderWorldYsThisRep = []
                rightShoulderWorldYsThisRep = []
                finalizePreviousRepTopPause(withStartTimestamp: timestamp)
                collectRepSample(from: pose, referenceY: noseY)

                let msg = formatDownLog(noseY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY)
                return RepUpdate(phase: .down, repCount: repCount, noseY: noseY,
                                 depthPercent: depthPercent(noseY, worldY: worldY), debugMessage: msg)
            }
        } else {
            resetCandidate()
        }

        framesSinceLastReadyDiag += 1
        let nearMissThreshold: CGFloat = 0.03
        if noseDelta > nearMissThreshold && !isGoingDown && framesSinceLastReadyDiag >= readyDiagInterval {
            framesSinceLastReadyDiag = 0
            var failedGates: [String] = []
            if !noseDown { failedGates.append("Δhead=\(f(noseDelta))<\(f(downThresholdFraction))") }
            if !shoulderDown { failedGates.append("Δshldr=\(f(shoulderDelta))<0.025") }
            if !relGatePass { failedGates.append("Δrel=\(f(relativeGap))<\(f(minimumRelativeGapForDescent))") }
            if let wristDrift, wristDrift > maxWristDrift { failedGates.append("wDrift>\(f(maxWristDrift))") }
            if let hipDrift, hipDrift > maxHipDrift { failedGates.append("hDrift>\(f(maxHipDrift))") }
            failedGates.append("score=\(descentScore)")
            let gateStr = failedGates.joined(separator: ", ")
            let msg = "NEAR-MISS | head=\(f(noseY)) Δhead=\(f(noseDelta)) Δrel=\(f(relativeGap)) | blocked by: \(gateStr)"
            return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: msg)
        }

        return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: nil)
    }

    private func handleDown(pose: PoseResult, noseY: CGFloat, worldY: Float?, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, timestamp: TimeInterval) -> RepUpdate {
        guard let baseline = baselineNoseY else {
            return RepUpdate(phase: currentPhase, repCount: repCount, noseY: noseY, depthPercent: nil, debugMessage: nil)
        }

        peakNoseY = max(peakNoseY, noseY)
        if peakNoseY == noseY {
            deepestTimestamp = timestamp
            lastDownProgressTimestamp = timestamp
        }
        if let smY = shoulderMidY {
            peakShoulderMidY = max(peakShoulderMidY, smY)
        }
        if let wy = worldY {
            minWorldYThisRep = min(minWorldYThisRep, wy)
            maxWorldYThisRep = max(maxWorldYThisRep, wy)
        }

        collectRepSample(from: pose, referenceY: noseY)

        let noseReturnDelta = peakNoseY - noseY
        let shoulderReturnDelta: CGFloat
        if let shoulderMidY, peakShoulderMidY > 0 {
            shoulderReturnDelta = peakShoulderMidY - shoulderMidY
        } else {
            shoulderReturnDelta = 0
        }
        let isComingUp = noseReturnDelta > upThresholdFraction || shoulderReturnDelta > (upThresholdFraction * 0.85)

        if isComingUp {
            if confirmTransition(to: .ascending) {
                let nosePeakDepth = peakNoseY - baseline
                let shoulderPeakDepth: CGFloat
                if let baselineShoulderMidY, peakShoulderMidY > 0 {
                    shoulderPeakDepth = peakShoulderMidY - baselineShoulderMidY
                } else {
                    shoulderPeakDepth = 0
                }
                let effectivePeakDepth = max(nosePeakDepth, shoulderPeakDepth * 0.9)
                let peakDepth = effectivePeakDepth >= minimumDepthGate
                guard peakDepth else {
                    return rejectCurrentRep(
                        reason: "shallow",
                        noseY: noseY,
                        worldY: worldY,
                        shoulderMidY: shoulderMidY,
                        hipMidY: hipMidY,
                        wristMidY: wristMidY,
                        timestamp: timestamp
                    )
                }

                let duration = timestamp - currentRepStartTime
                guard duration >= minimumRepDuration else {
                    return rejectCurrentRep(
                        reason: "too fast \(String(format: "%.2fs", duration))",
                        noseY: noseY,
                        worldY: worldY,
                        shoulderMidY: shoulderMidY,
                        hipMidY: hipMidY,
                        wristMidY: wristMidY,
                        timestamp: timestamp
                    )
                }

                guard duration <= maximumRepDuration else {
                    return rejectCurrentRep(
                        reason: "too slow \(String(format: "%.1fs", duration))",
                        noseY: noseY,
                        worldY: worldY,
                        shoulderMidY: shoulderMidY,
                        hipMidY: hipMidY,
                        wristMidY: wristMidY,
                        timestamp: timestamp
                    )
                }

                let eccentric = max(0, deepestTimestamp - currentRepStartTime)
                let bottomPause = max(0, timestamp - deepestTimestamp)
                pendingMeasurement = buildPendingMeasurement(
                    baseline: baseline,
                    duration: duration,
                    eccentricDuration: eccentric,
                    bottomPauseDuration: bottomPause
                )
                currentPhase = .ascending
                ascendingStartTime = timestamp
                framesNearBaseline = 0
                ascendingSamples = repSamples.suffix(4).map { $0 }

                let msg = formatAscendingLog(noseY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, duration: duration)
                return RepUpdate(phase: .ascending, repCount: repCount, noseY: noseY,
                                 depthPercent: depthPercent(noseY, worldY: worldY), debugMessage: msg)
            }
        } else {
            resetCandidate()
        }

        let duration = timestamp - currentRepStartTime
        let stalledTooLong = duration > stalledDownTimeoutSeconds && (timestamp - lastDownProgressTimestamp) > 0.8
        if stalledTooLong {
            return rejectCurrentRep(
                reason: pose.isPushupLikeBodyOrientation ? "stalled in down" : "setup broke during descent",
                noseY: noseY,
                worldY: worldY,
                shoulderMidY: shoulderMidY,
                hipMidY: hipMidY,
                wristMidY: wristMidY,
                timestamp: timestamp
            )
        }

        return RepUpdate(phase: .down, repCount: repCount, noseY: noseY,
                         depthPercent: depthPercent(noseY, worldY: worldY), debugMessage: nil)
    }

    private func handleAscending(pose: PoseResult, noseY: CGFloat, worldY: Float?, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, timestamp: TimeInterval) -> RepUpdate {
        guard let bNose = baselineNoseY else {
            currentPhase = .ready
            return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: nil)
        }

        collectRepSample(from: pose, referenceY: noseY)
        ascendingSamples.append(RepFrameSample(
            timestamp: timestamp,
            referenceY: noseY,
            shoulderMidY: shoulderMidY,
            hipMidY: hipMidY,
            wristMidY: wristMidY,
            shoulderMidX: computeShoulderMidX(from: pose),
            hipMidX: computeHipMidX(from: pose),
            torsoAngleToFloor: torsoAngleToFloor(from: pose),
            bodyLineAngle: bodyLineAngle(from: pose),
            headAlignmentAngle: headAlignmentAngle(from: pose),
            leftElbowFlare: elbowFlareAngle(from: pose, side: .left),
            rightElbowFlare: elbowFlareAngle(from: pose, side: .right),
            leftForearmVerticality: forearmVerticality(from: pose, side: .left),
            rightForearmVerticality: forearmVerticality(from: pose, side: .right),
            leftHipY: pose.landmark(.leftHip)?.position.y,
            rightHipY: pose.landmark(.rightHip)?.position.y
        ))

        if timestamp - ascendingStartTime > ascendingTimeoutSeconds {
            noteRejection("ascending timeout")
            let msg = "TIMEOUT (\(String(format: "%.1fs", timestamp - ascendingStartTime)) in ascending) — return to top and relock start position"
            pendingMeasurement = nil
            currentPhase = .idle
            readyPoseStreak = 0
            resetCandidate()
            resetRepTracking()
            clearBaselines()
            bootstrapSamples.removeAll()
            return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil, debugMessage: msg)
        }

        let noseNearBaseline = abs(noseY - bNose) < returnToBaselineTolerance
        let shoulderNearBaseline: Bool
        if let smY = shoulderMidY, let bsY = baselineShoulderMidY {
            shoulderNearBaseline = abs(smY - bsY) < shoulderReturnTolerance
        } else {
            shoulderNearBaseline = true
        }

        if noseNearBaseline && shoulderNearBaseline {
            framesNearBaseline += 1
            if framesNearBaseline >= ascendingConfirmFrames {
                guard var measurement = pendingMeasurement else {
                    currentPhase = .ready
                    return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: nil)
                }

                measurement.concentricDurationSeconds = max(0, timestamp - ascendingStartTime)
                measurement.topLockoutCompleteness = min(
                    1,
                    Double(max(0, 1 - (abs(noseY - bNose) / max(returnToBaselineTolerance, 0.001))))
                )
                completedReps.append(measurement)
                repCount += 1
                pendingMeasurement = nil

                calibrateIfNeeded()

                let msg = formatRepLog(repNumber: repCount, noseY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, duration: measurement.durationSeconds)

                resetRepTracking()
                updateBaselines(noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, wristMidY: wristMidY, hipMidY: hipMidY)
                lastRepCompletionTime = timestamp
                currentPhase = .ready
                return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: msg)
            }
        } else {
            framesNearBaseline = 0
        }

        return RepUpdate(phase: .ascending, repCount: repCount, noseY: noseY,
                         depthPercent: depthPercent(noseY, worldY: worldY), debugMessage: nil)
    }

    private func rejectCurrentRep(reason: String, noseY: CGFloat, worldY: Float?, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, timestamp: TimeInterval) -> RepUpdate {
        noteRejection(reason)
        let duration = timestamp - currentRepStartTime
        let msg = formatRejectLog(reason: reason, noseY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, duration: duration)
        resetCandidate()
        currentPhase = .ready
        updateBaselines(noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, wristMidY: wristMidY, hipMidY: hipMidY)
        resetRepTracking()
        return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: msg)
    }

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

    private func computeShoulderMidY(from pose: PoseResult) -> CGFloat? {
        guard let ls = pose.landmark(.leftShoulder), let rs = pose.landmark(.rightShoulder),
              ls.confidence >= 0.3, rs.confidence >= 0.3 else { return nil }
        return (ls.position.y + rs.position.y) * 0.5
    }

    private func computeShoulderMidX(from pose: PoseResult) -> CGFloat? {
        guard let ls = pose.landmark(.leftShoulder), let rs = pose.landmark(.rightShoulder),
              ls.confidence >= 0.3, rs.confidence >= 0.3 else { return nil }
        return (ls.position.x + rs.position.x) * 0.5
    }

    private func computeHipMidY(from pose: PoseResult) -> CGFloat? {
        guard let lh = pose.landmark(.leftHip), let rh = pose.landmark(.rightHip),
              lh.confidence >= 0.2, rh.confidence >= 0.2 else { return nil }
        return (lh.position.y + rh.position.y) * 0.5
    }

    private func computeHipMidX(from pose: PoseResult) -> CGFloat? {
        guard let lh = pose.landmark(.leftHip), let rh = pose.landmark(.rightHip),
              lh.confidence >= 0.2, rh.confidence >= 0.2 else { return nil }
        return (lh.position.x + rh.position.x) * 0.5
    }

    private func computeWristMidY(from pose: PoseResult) -> CGFloat? {
        guard let lw = pose.landmark(.leftWrist), let rw = pose.landmark(.rightWrist),
              lw.confidence >= 0.2, rw.confidence >= 0.2 else { return nil }
        return (lw.position.y + rw.position.y) * 0.5
    }

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

    private func lockBaseline(noseY: CGFloat, worldY: Float?, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?) {
        baselineNoseY = noseY
        baselineWorldY = worldY
        let sanitizedShoulder = sanitizedShoulderMidY(shoulderMidY, referenceY: noseY)
        let sanitizedHip = sanitizedHipMidY(hipMidY, shoulderMidY: sanitizedShoulder)
        baselineShoulderMidY = sanitizedShoulder
        baselineWristMidY = sanitizedWristMidY(wristMidY, shoulderMidY: sanitizedShoulder, hipMidY: sanitizedHip)
        baselineHipMidY = sanitizedHip
    }

    private func updateBaselines(noseY: CGFloat, worldY: Float?, shoulderMidY: CGFloat?, wristMidY: CGFloat?, hipMidY: CGFloat?) {
        lockBaseline(noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY)
    }

    private func resetRepTracking() {
        peakNoseY = 0.0
        peakShoulderMidY = 0.0
        minWorldYThisRep = .greatestFiniteMagnitude
        maxWorldYThisRep = -.greatestFiniteMagnitude
        repSamples = []
        ascendingSamples = []
        deepestTimestamp = 0
        lastDownProgressTimestamp = 0
    }

    private func clearBaselines() {
        baselineNoseY = nil
        baselineWorldY = nil
        baselineShoulderMidY = nil
        baselineWristMidY = nil
        baselineHipMidY = nil
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

    private func recordBootstrapSample(referenceY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, timestamp: TimeInterval) {
        let sanitizedShoulder = sanitizedShoulderMidY(shoulderMidY, referenceY: referenceY)
        let sanitizedHip = sanitizedHipMidY(hipMidY, shoulderMidY: sanitizedShoulder)
        let sanitizedWrist = sanitizedWristMidY(wristMidY, shoulderMidY: sanitizedShoulder, hipMidY: sanitizedHip)
        guard isPlausibleAnchorFrame(referenceY: referenceY, shoulderMidY: sanitizedShoulder, hipMidY: sanitizedHip, wristMidY: sanitizedWrist) else {
            let cutoff = timestamp - 1.5
            bootstrapSamples.removeAll { $0.timestamp < cutoff }
            return
        }

        bootstrapSamples.append(
            BootstrapSample(
                timestamp: timestamp,
                referenceY: referenceY,
                shoulderMidY: sanitizedShoulder,
                hipMidY: sanitizedHip,
                wristMidY: sanitizedWrist
            )
        )
        let cutoff = timestamp - 1.5
        bootstrapSamples.removeAll { $0.timestamp < cutoff }
    }

    private func bootstrapCandidate(currentY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?) -> BootstrapSample? {
        guard bootstrapSamples.count >= 8 else { return nil }
        let currentShoulder = sanitizedShoulderMidY(shoulderMidY, referenceY: currentY)
        let currentHip = sanitizedHipMidY(hipMidY, shoulderMidY: currentShoulder)
        let currentWrist = sanitizedWristMidY(wristMidY, shoulderMidY: currentShoulder, hipMidY: currentHip)
        guard isPlausibleAnchorFrame(referenceY: currentY, shoulderMidY: currentShoulder, hipMidY: currentHip, wristMidY: currentWrist) else {
            return nil
        }
        guard let top = bootstrapSamples.min(by: { $0.referenceY < $1.referenceY }) else { return nil }
        let travel = currentY - top.referenceY
        guard travel >= bootstrapDownThreshold else { return nil }

        let relativeGap: CGFloat
        if let currentShoulder, let topShoulder = top.shoulderMidY {
            relativeGap = travel - (currentShoulder - topShoulder)
        } else {
            relativeGap = travel
        }
        guard relativeGap >= -0.03 || travel >= bootstrapDownThreshold + 0.02 else { return nil }

        if let currentWrist, let topWrist = top.wristMidY, abs(currentWrist - topWrist) > maxWristDrift * 1.7 {
            return nil
        }
        if let currentHip, let topHip = top.hipMidY, abs(currentHip - topHip) > maxHipDrift * 1.6 {
            return nil
        }

        return top
    }

    private func sanitizedShoulderMidY(_ shoulderMidY: CGFloat?, referenceY: CGFloat) -> CGFloat? {
        guard let shoulderMidY, shoulderMidY.isFinite else { return nil }
        guard shoulderMidY >= 0.12, shoulderMidY <= 0.88 else { return nil }
        guard shoulderMidY >= referenceY - 0.14 else { return nil }
        guard shoulderMidY <= referenceY + 0.22 else { return nil }
        return shoulderMidY
    }

    private func sanitizedHipMidY(_ hipMidY: CGFloat?, shoulderMidY: CGFloat?) -> CGFloat? {
        guard let hipMidY, hipMidY.isFinite else { return nil }
        guard hipMidY >= 0.18, hipMidY <= 0.98 else { return nil }
        if let shoulderMidY {
            guard hipMidY >= shoulderMidY - 0.04 else { return nil }
            guard hipMidY - shoulderMidY <= 0.42 else { return nil }
        }
        return hipMidY
    }

    private func sanitizedWristMidY(_ wristMidY: CGFloat?, shoulderMidY: CGFloat?, hipMidY: CGFloat?) -> CGFloat? {
        guard let wristMidY, wristMidY.isFinite else { return nil }
        guard wristMidY >= 0.22, wristMidY <= 0.99 else { return nil }
        if let shoulderMidY {
            guard wristMidY >= shoulderMidY + 0.08 else { return nil }
        }
        if let hipMidY {
            guard wristMidY >= hipMidY - 0.10 else { return nil }
        }
        return wristMidY
    }

    private func isPlausibleAnchorFrame(referenceY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?) -> Bool {
        guard referenceY.isFinite, referenceY >= 0.04, referenceY <= 0.96 else { return false }
        guard shoulderMidY != nil else { return false }
        let anchorCount = [shoulderMidY, hipMidY, wristMidY].compactMap { $0 }.count
        guard anchorCount >= 2 else { return false }
        return true
    }

    private func finalizePreviousRepTopPause(withStartTimestamp timestamp: TimeInterval) {
        guard let lastRepCompletionTime, !completedReps.isEmpty else { return }
        completedReps[completedReps.count - 1].topPauseDurationSeconds = max(0, timestamp - lastRepCompletionTime)
    }

    private func collectRepSample(from pose: PoseResult, referenceY: CGFloat) {
        repSamples.append(
            RepFrameSample(
                timestamp: pose.timestamp,
                referenceY: referenceY,
                shoulderMidY: computeShoulderMidY(from: pose),
                hipMidY: computeHipMidY(from: pose),
                wristMidY: computeWristMidY(from: pose),
                shoulderMidX: computeShoulderMidX(from: pose),
                hipMidX: computeHipMidX(from: pose),
                torsoAngleToFloor: torsoAngleToFloor(from: pose),
                bodyLineAngle: bodyLineAngle(from: pose),
                headAlignmentAngle: headAlignmentAngle(from: pose),
                leftElbowFlare: elbowFlareAngle(from: pose, side: .left),
                rightElbowFlare: elbowFlareAngle(from: pose, side: .right),
                leftForearmVerticality: forearmVerticality(from: pose, side: .left),
                rightForearmVerticality: forearmVerticality(from: pose, side: .right),
                leftHipY: pose.landmark(.leftHip)?.position.y,
                rightHipY: pose.landmark(.rightHip)?.position.y
            )
        )
    }

    private func buildPendingMeasurement(baseline: CGFloat, duration: TimeInterval, eccentricDuration: TimeInterval, bottomPauseDuration: TimeInterval) -> RepMeasurement {
        let shoulderAsymmetryWorld = minWorldYThisRep == .greatestFiniteMagnitude ? nil : minWorldYThisRep
        _ = shoulderAsymmetryWorld

        let hipAsymmetry = averagePairedDifference(left: repSamples.compactMap(\.leftHipY), right: repSamples.compactMap(\.rightHipY))
        let elbowFlare = averageOptional(repSamples.compactMap(\.leftElbowFlare) + repSamples.compactMap(\.rightElbowFlare))
        let leftFlare = averageOptional(repSamples.compactMap(\.leftElbowFlare))
        let rightFlare = averageOptional(repSamples.compactMap(\.rightElbowFlare))
        let elbowSymmetry: Double?
        if let leftFlare, let rightFlare {
            elbowSymmetry = abs(leftFlare - rightFlare)
        } else {
            elbowSymmetry = nil
        }
        let forearmVerticality = averageOptional(repSamples.compactMap(\.leftForearmVerticality) + repSamples.compactMap(\.rightForearmVerticality))
        let torsoAngle = averageOptional(repSamples.compactMap(\.torsoAngleToFloor))
        let bodyLine = bodyLineStraightnessScore(from: repSamples.compactMap(\.bodyLineAngle))
        let headAlignment = averageOptional(repSamples.compactMap(\.headAlignmentAngle))
        let lateralDrift = lateralDrift(from: repSamples)
        let jerkiness = pathJerkiness(from: repSamples)
        let stickingPoint = stickingPointPercent(from: ascendingSamples, topY: baseline, bottomY: peakNoseY)
        let wobbleEvents = wobbleEvents(from: repSamples)
        let centerDrift = lateralDrift

        return RepMeasurement(
            minNoseY: peakNoseY,
            maxNoseY: baseline,
            minWorldY: minWorldYThisRep == .greatestFiniteMagnitude ? nil : minWorldYThisRep,
            maxWorldY: maxWorldYThisRep == -.greatestFiniteMagnitude ? nil : maxWorldYThisRep,
            durationSeconds: duration,
            eccentricDurationSeconds: eccentricDuration,
            bottomPauseDurationSeconds: bottomPauseDuration,
            concentricDurationSeconds: 0,
            topPauseDurationSeconds: 0,
            topPositionY: baseline,
            bottomPositionY: peakNoseY,
            topLockoutCompleteness: 0,
            leftShoulderYs: leftShoulderYsThisRep,
            rightShoulderYs: rightShoulderYsThisRep,
            leftShoulderWorldYs: leftShoulderWorldYsThisRep,
            rightShoulderWorldYs: rightShoulderWorldYsThisRep,
            hipAsymmetry: hipAsymmetry,
            elbowFlareAngle: elbowFlare,
            elbowSymmetry: elbowSymmetry,
            forearmVerticality: forearmVerticality,
            torsoAngleToFloor: torsoAngle,
            bodyLineStraightness: bodyLine,
            headAlignment: headAlignment,
            lateralDrift: lateralDrift,
            centerOfMassDriftProxy: centerDrift,
            pathJerkiness: jerkiness,
            stickingPointPercent: stickingPoint,
            wobbleEvents: wobbleEvents
        )
    }

    private func averagePairedDifference(left: [CGFloat], right: [CGFloat]) -> Double {
        let pairCount = min(left.count, right.count)
        guard pairCount > 0 else { return 0 }
        let total = (0..<pairCount).reduce(0.0) { partial, index in
            partial + Double(abs(left[index] - right[index]))
        }
        return total / Double(pairCount)
    }

    private func averageOptional(_ values: [CGFloat]) -> Double? {
        guard !values.isEmpty else { return nil }
        let total = values.reduce(0.0) { $0 + Double($1) }
        return total / Double(values.count)
    }

    private func lateralDrift(from samples: [RepFrameSample]) -> Double {
        let xs = samples.compactMap { sample -> CGFloat? in
            if let shoulder = sample.shoulderMidX, let hip = sample.hipMidX {
                return (shoulder + hip) * 0.5
            }
            return sample.shoulderMidX ?? sample.hipMidX
        }
        guard let minX = xs.min(), let maxX = xs.max() else { return 0 }
        return Double(maxX - minX)
    }

    private func wobbleEvents(from samples: [RepFrameSample]) -> Int {
        let xs = samples.compactMap { sample -> CGFloat? in
            if let shoulder = sample.shoulderMidX, let hip = sample.hipMidX {
                return (shoulder + hip) * 0.5
            }
            return sample.shoulderMidX ?? sample.hipMidX
        }
        guard xs.count >= 3 else { return 0 }

        var wobbleCount = 0
        var lastDirection = 0
        for index in 1..<xs.count {
            let delta = xs[index] - xs[index - 1]
            let direction = delta > 0.004 ? 1 : (delta < -0.004 ? -1 : 0)
            if direction != 0 && lastDirection != 0 && direction != lastDirection {
                wobbleCount += 1
            }
            if direction != 0 {
                lastDirection = direction
            }
        }
        return wobbleCount
    }

    private func pathJerkiness(from samples: [RepFrameSample]) -> Double? {
        guard samples.count >= 3 else { return nil }
        var accelerations: [Double] = []
        for index in 2..<samples.count {
            let dt1 = max(samples[index - 1].timestamp - samples[index - 2].timestamp, 0.001)
            let dt2 = max(samples[index].timestamp - samples[index - 1].timestamp, 0.001)
            let v1 = Double(samples[index - 1].referenceY - samples[index - 2].referenceY) / dt1
            let v2 = Double(samples[index].referenceY - samples[index - 1].referenceY) / dt2
            accelerations.append(abs(v2 - v1))
        }
        guard !accelerations.isEmpty else { return nil }
        return accelerations.reduce(0, +) / Double(accelerations.count)
    }

    private func stickingPointPercent(from samples: [RepFrameSample], topY: CGFloat, bottomY: CGFloat) -> Double? {
        guard samples.count >= 3, bottomY > topY else { return nil }
        var minSpeed = Double.greatestFiniteMagnitude
        var minProgress: Double?
        for index in 1..<samples.count {
            let dt = max(samples[index].timestamp - samples[index - 1].timestamp, 0.001)
            let velocity = Double(samples[index - 1].referenceY - samples[index].referenceY) / dt
            if velocity < minSpeed {
                minSpeed = velocity
                let progress = Double((bottomY - samples[index].referenceY) / max(bottomY - topY, 0.001))
                minProgress = min(max(progress, 0), 1)
            }
        }
        return minProgress
    }

    private func bodyLineStraightnessScore(from angles: [CGFloat]) -> Double? {
        guard !angles.isEmpty else { return nil }
        let deviations = angles.map { abs(180 - Double($0)) }
        return deviations.reduce(0, +) / Double(deviations.count)
    }

    private enum Side {
        case left
        case right
    }

    private func torsoAngleToFloor(from pose: PoseResult) -> CGFloat? {
        guard let trunk = pose.trunkAngleFromVertical else { return nil }
        return max(0, 90 - trunk)
    }

    private func bodyLineAngle(from pose: PoseResult) -> CGFloat? {
        let options: [(LandmarkType, LandmarkType, LandmarkType)] = [
            (.leftShoulder, .leftHip, .leftAnkle),
            (.rightShoulder, .rightHip, .rightAnkle),
            (.leftShoulder, .leftHip, .leftKnee),
            (.rightShoulder, .rightHip, .rightKnee),
        ]
        let angles = options.compactMap { shoulder, hip, leg -> CGFloat? in
            guard let s = pose.landmark(shoulder), let h = pose.landmark(hip), let l = pose.landmark(leg),
                  s.confidence >= 0.18, h.confidence >= 0.18, l.confidence >= 0.18 else { return nil }
            return vertexAngleDegrees(pA: s.position, vertex: h.position, pB: l.position)
        }
        guard !angles.isEmpty else { return nil }
        return angles.reduce(0, +) / CGFloat(angles.count)
    }

    private func headAlignmentAngle(from pose: PoseResult) -> CGFloat? {
        guard let headY = pose.headReferenceY,
              let ls = pose.landmark(.leftShoulder), let rs = pose.landmark(.rightShoulder),
              ls.confidence >= 0.18, rs.confidence >= 0.18 else { return nil }
        let shoulderMid = CGPoint(x: (ls.position.x + rs.position.x) * 0.5, y: (ls.position.y + rs.position.y) * 0.5)
        let headXValues = [
            pose.landmark(.nose)?.position.x,
            pose.landmark(.leftEye)?.position.x,
            pose.landmark(.rightEye)?.position.x,
        ].compactMap { $0 }
        let headX = headXValues.isEmpty ? shoulderMid.x : headXValues.reduce(0, +) / CGFloat(headXValues.count)
        if let lh = pose.landmark(.leftHip), let rh = pose.landmark(.rightHip), lh.confidence >= 0.18, rh.confidence >= 0.18 {
            let hipMid = CGPoint(x: (lh.position.x + rh.position.x) * 0.5, y: (lh.position.y + rh.position.y) * 0.5)
            return vertexAngleDegrees(pA: CGPoint(x: headX, y: headY), vertex: shoulderMid, pB: hipMid)
        }
        return nil
    }

    private func elbowFlareAngle(from pose: PoseResult, side: Side) -> CGFloat? {
        let shoulderType: LandmarkType = side == .left ? .leftShoulder : .rightShoulder
        let elbowType: LandmarkType = side == .left ? .leftElbow : .rightElbow
        let hipType: LandmarkType = side == .left ? .leftHip : .rightHip
        guard let shoulder = pose.landmark(shoulderType),
              let elbow = pose.landmark(elbowType),
              let hip = pose.landmark(hipType),
              shoulder.confidence >= 0.18,
              elbow.confidence >= 0.18,
              hip.confidence >= 0.18 else { return nil }
        return vertexAngleDegrees(pA: elbow.position, vertex: shoulder.position, pB: hip.position)
    }

    private func forearmVerticality(from pose: PoseResult, side: Side) -> CGFloat? {
        let elbowType: LandmarkType = side == .left ? .leftElbow : .rightElbow
        let wristType: LandmarkType = side == .left ? .leftWrist : .rightWrist
        guard let elbow = pose.landmark(elbowType),
              let wrist = pose.landmark(wristType),
              elbow.confidence >= 0.18,
              wrist.confidence >= 0.18 else { return nil }
        let dx = wrist.position.x - elbow.position.x
        let dy = wrist.position.y - elbow.position.y
        return atan2(abs(dx), abs(dy)) * 180 / .pi
    }

    private func vertexAngleDegrees(pA: CGPoint, vertex: CGPoint, pB: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: pA.x - vertex.x, y: pA.y - vertex.y)
        let v2 = CGPoint(x: pB.x - vertex.x, y: pB.y - vertex.y)
        let d1 = hypot(v1.x, v1.y)
        let d2 = hypot(v2.x, v2.y)
        guard d1 > 1e-5, d2 > 1e-5 else { return 180 }
        let dot = (v1.x * v2.x + v1.y * v2.y) / (d1 * d2)
        return acos(min(1, max(-1, dot))) * 180 / .pi
    }

    private func noteRejection(_ reason: String) {
        rejectionCounts[reason, default: 0] += 1
    }

    private func f(_ v: CGFloat) -> String { String(format: "%.3f", v) }
    private func fo(_ v: CGFloat?) -> String { v.map { f($0) } ?? "n/a" }

    private func driftStr(current: CGFloat?, baseline: CGFloat?) -> String {
        guard let c = current, let b = baseline else { return "n/a" }
        return f(abs(c - b))
    }

    private func formatLockLog(noseY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?) -> String {
        let relGap = shoulderMidY.map { noseY - $0 }
        return "LOCKED | head=\(f(noseY)) shldr=\(fo(shoulderMidY)) hip=\(fo(hipMidY)) wrist=\(fo(wristMidY)) rel=\(fo(relGap))"
    }

    private func formatDownLog(noseY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?) -> String {
        let dn = baselineNoseY.map { noseY - $0 }
        let ds = (shoulderMidY != nil && baselineShoulderMidY != nil) ? shoulderMidY! - baselineShoulderMidY! : nil as CGFloat?
        let dr = (dn != nil && ds != nil) ? dn! - ds! : nil as CGFloat?
        return "DOWN | head=\(f(noseY)) shldr=\(fo(shoulderMidY)) hip=\(fo(hipMidY)) wrist=\(fo(wristMidY)) | Δhead=\(fo(dn)) Δshldr=\(fo(ds)) Δrel=\(fo(dr)) wDrift=\(driftStr(current: wristMidY, baseline: baselineWristMidY)) hDrift=\(driftStr(current: hipMidY, baseline: baselineHipMidY))"
    }

    private func formatAscendingLog(noseY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, duration: TimeInterval) -> String {
        let dn = baselineNoseY.map { peakNoseY - $0 }
        let ds = baselineShoulderMidY.map { peakShoulderMidY - $0 }
        let dr = (dn != nil && ds != nil) ? dn! - ds! : nil as CGFloat?
        return "ASCENDING dur=\(String(format: "%.2fs", duration)) | head=\(f(noseY)) shldr=\(fo(shoulderMidY)) hip=\(fo(hipMidY)) wrist=\(fo(wristMidY)) | Δhead=\(fo(dn)) Δshldr=\(fo(ds)) Δrel=\(fo(dr)) wDrift=\(driftStr(current: wristMidY, baseline: baselineWristMidY)) hDrift=\(driftStr(current: hipMidY, baseline: baselineHipMidY)) | peak: head=\(f(peakNoseY)) shldr=\(f(peakShoulderMidY))"
    }

    private func formatRepLog(repNumber: Int, noseY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, duration: TimeInterval) -> String {
        let dn = baselineNoseY.map { peakNoseY - $0 }
        let ds = baselineShoulderMidY.map { peakShoulderMidY - $0 }
        let dr = (dn != nil && ds != nil) ? dn! - ds! : nil as CGFloat?
        return "REP #\(repNumber) dur=\(String(format: "%.2fs", duration)) | head=\(f(noseY)) shldr=\(fo(shoulderMidY)) hip=\(fo(hipMidY)) wrist=\(fo(wristMidY)) | Δhead=\(fo(dn)) Δshldr=\(fo(ds)) Δrel=\(fo(dr)) wDrift=\(driftStr(current: wristMidY, baseline: baselineWristMidY)) hDrift=\(driftStr(current: hipMidY, baseline: baselineHipMidY)) | peak: head=\(f(peakNoseY)) shldr=\(f(peakShoulderMidY))"
    }

    private func formatRejectLog(reason: String, noseY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, duration: TimeInterval) -> String {
        let dn = baselineNoseY.map { peakNoseY - $0 }
        let ds = baselineShoulderMidY.map { peakShoulderMidY - $0 }
        let dr = (dn != nil && ds != nil) ? dn! - ds! : nil as CGFloat?
        return "REJECTED (\(reason)) dur=\(String(format: "%.2fs", duration)) | head=\(f(noseY)) shldr=\(fo(shoulderMidY)) hip=\(fo(hipMidY)) wrist=\(fo(wristMidY)) | Δhead=\(fo(dn)) Δshldr=\(fo(ds)) Δrel=\(fo(dr)) wDrift=\(driftStr(current: wristMidY, baseline: baselineWristMidY)) hDrift=\(driftStr(current: hipMidY, baseline: baselineHipMidY))"
    }
}

struct RepCountingScenarioResult {
    let name: String
    let repCount: Int
    let diagnostics: RepCountingEngine.DiagnosticsSnapshot
}

enum RepCountingScenarioHarness {
    static func defaultScenarios() -> [RepCountingScenarioResult] {
        [
            runScenario(name: "face_down", headLift: 0.0, unstableHead: false, distanceScale: 1.0, bootstrapStart: false),
            runScenario(name: "face_toward_camera", headLift: -0.06, unstableHead: false, distanceScale: 1.0, bootstrapStart: false),
            runScenario(name: "mild_neck_rotation", headLift: -0.03, unstableHead: true, distanceScale: 1.0, bootstrapStart: false),
            runScenario(name: "too_close_but_usable", headLift: -0.04, unstableHead: false, distanceScale: 1.25, bootstrapStart: false),
            runScenario(name: "too_far_but_usable", headLift: -0.03, unstableHead: false, distanceScale: 0.82, bootstrapStart: false),
            runScenario(name: "bootstrap_mid_motion", headLift: -0.02, unstableHead: true, distanceScale: 1.0, bootstrapStart: true),
        ]
    }

    static func runScenario(name: String, headLift: CGFloat, unstableHead: Bool, distanceScale: CGFloat, bootstrapStart: Bool) -> RepCountingScenarioResult {
        let engine = RepCountingEngine()
        let frames = makeFrames(headLift: headLift, unstableHead: unstableHead, distanceScale: distanceScale, bootstrapStart: bootstrapStart)
        for frame in frames {
            _ = engine.update(with: frame)
        }
        return RepCountingScenarioResult(name: name, repCount: engine.repCount, diagnostics: engine.diagnosticsSnapshot)
    }

    private static func makeFrames(headLift: CGFloat, unstableHead: Bool, distanceScale: CGFloat, bootstrapStart: Bool) -> [PoseResult] {
        let totalFrames = 90
        let startFrame = bootstrapStart ? 8 : 0
        return (0..<totalFrames).map { index in
            let progress = max(0, Double(index - startFrame)) / 30.0
            let cycle = min(progress, 2.0)
            let descent = cycle <= 1.0 ? cycle : (2.0 - cycle)
            let headYOffset = CGFloat(descent) * 0.16 + headLift

            let shoulderSpan = 0.12 * distanceScale
            let shoulderMid = CGPoint(x: 0.5, y: 0.44)
            let hipMid = CGPoint(x: 0.5, y: 0.52 + CGFloat(descent) * 0.01)
            let headY = shoulderMid.y + 0.02 + headYOffset
            let jitter: CGFloat = unstableHead && index % 7 == 0 ? 0.015 : 0

            let landmarks: [Landmark] = [
                Landmark(type: .nose, position: CGPoint(x: 0.5 + jitter, y: headY), confidence: unstableHead && index % 7 == 0 ? 0.24 : 0.8),
                Landmark(type: .leftEye, position: CGPoint(x: 0.48, y: headY - 0.01), confidence: 0.72),
                Landmark(type: .rightEye, position: CGPoint(x: 0.52, y: headY - 0.01), confidence: 0.72),
                Landmark(type: .leftShoulder, position: CGPoint(x: shoulderMid.x - shoulderSpan * 0.5, y: shoulderMid.y + CGFloat(descent) * 0.02), confidence: 0.86),
                Landmark(type: .rightShoulder, position: CGPoint(x: shoulderMid.x + shoulderSpan * 0.5, y: shoulderMid.y + CGFloat(descent) * 0.02), confidence: 0.86),
                Landmark(type: .leftElbow, position: CGPoint(x: shoulderMid.x - shoulderSpan * 0.9, y: 0.58), confidence: 0.74),
                Landmark(type: .rightElbow, position: CGPoint(x: shoulderMid.x + shoulderSpan * 0.9, y: 0.58), confidence: 0.74),
                Landmark(type: .leftWrist, position: CGPoint(x: shoulderMid.x - shoulderSpan * 1.0, y: 0.72), confidence: 0.8),
                Landmark(type: .rightWrist, position: CGPoint(x: shoulderMid.x + shoulderSpan * 1.0, y: 0.72), confidence: 0.8),
                Landmark(type: .leftHip, position: CGPoint(x: hipMid.x - 0.05, y: hipMid.y), confidence: 0.82),
                Landmark(type: .rightHip, position: CGPoint(x: hipMid.x + 0.05, y: hipMid.y), confidence: 0.82),
                Landmark(type: .leftKnee, position: CGPoint(x: 0.42, y: 0.66), confidence: 0.6),
                Landmark(type: .rightKnee, position: CGPoint(x: 0.58, y: 0.66), confidence: 0.6),
                Landmark(type: .leftAnkle, position: CGPoint(x: 0.42, y: 0.8), confidence: 0.55),
                Landmark(type: .rightAnkle, position: CGPoint(x: 0.58, y: 0.8), confidence: 0.55),
            ]
            return PoseResult(landmarks: landmarks, worldLandmarks: nil, timestamp: Double(index) / 30.0)
        }
    }
}
