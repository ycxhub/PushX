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

    private(set) var repCount: Int = 0
    private(set) var currentPhase: Phase = .idle

    // MARK: - Baseline state (captured on lock, updated after each rep)

    private var baselineNoseY: CGFloat?
    private var baselineWorldY: Float?
    private var baselineShoulderMidY: CGFloat?
    private var baselineWristMidY: CGFloat?
    private var baselineHipMidY: CGFloat?

    // MARK: - Per-rep tracking

    private var peakNoseY: CGFloat = 0.0
    private var peakShoulderMidY: CGFloat = 0.0
    private var minWorldYThisRep: Float = .greatestFiniteMagnitude
    private var maxWorldYThisRep: Float = -.greatestFiniteMagnitude

    // MARK: - Thresholds

    private let framesRequired = 6
    private var framesInCandidate = 0
    private var candidatePhase: Phase?

    private let downThresholdFraction: CGFloat = 0.10
    private let upThresholdFraction: CGFloat = 0.05

    /// Nose must descend MORE than shoulders by at least this amount (rejects equal-magnitude sway).
    private let minimumRelativeGapForDescent: CGFloat = 0.02

    /// Maximum wrist drift from baseline allowed during descent (rejects whole-body translation).
    private let maxWristDrift: CGFloat = 0.05

    /// Maximum hip drift from baseline allowed during descent (rejects kneeling / posture break).
    private let maxHipDrift: CGFloat = 0.08

    /// Minimum nose-Y travel from baseline to count as a valid rep.
    private let minimumDepthGate: CGFloat = 0.08

    /// Minimum duration for a rep to be valid.
    private let minimumRepDuration: TimeInterval = 0.35

    /// Maximum duration for a rep to be valid (rejects stuck-in-DOWN artifacts).
    private let maximumRepDuration: TimeInterval = 8.0

    // MARK: - Ascending phase (return-to-top confirmation)

    /// Nose must return to within this tolerance of baseline.
    private let returnToBaselineTolerance: CGFloat = 0.06
    /// Shoulders must return to within this tolerance of baseline.
    private let shoulderReturnTolerance: CGFloat = 0.04
    /// Consecutive frames near baseline required to confirm return.
    private let ascendingConfirmFrames = 4
    /// Maximum time in ascending before giving up.
    private let ascendingTimeoutSeconds: TimeInterval = 5.0

    private var ascendingStartTime: TimeInterval = 0
    private var framesNearBaseline: Int = 0
    private var pendingMeasurement: RepMeasurement?

    // MARK: - Pause / idle

    private var framesWithoutPose = 0
    private let pauseFrameThreshold = 15
    private var phaseBeforePause: Phase = .idle
    private var readyPoseStreak = 0
    private let framesRequiredForReadyLock = 30

    /// Throttle "near miss" diagnostics in ready phase to avoid log spam.
    private var framesSinceLastReadyDiag = 0
    private let readyDiagInterval = 60

    // MARK: - Adaptive calibration

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

    /// Whether world coordinates are available (used for depth display only, NOT for gate decisions).
    private var useWorldCoords = false

    // MARK: - Public API

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
        let shoulderMidY = computeShoulderMidY(from: pose)
        let hipMidY = computeHipMidY(from: pose)
        let wristMidY = computeWristMidY(from: pose)

        collectShoulderData(from: pose)

        switch currentPhase {
        case .idle:
            return handleIdle(pose: pose, noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY)
        case .ready:
            return handleReady(noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, timestamp: pose.timestamp)
        case .down:
            return handleDown(noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, timestamp: pose.timestamp)
        case .ascending:
            return handleAscending(noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, timestamp: pose.timestamp)
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
        maxExpectedTravel = 0.15
        maxExpectedWorldTravel = 0.12
        calibrationLocked = false
        useWorldCoords = false
        ascendingStartTime = 0
        framesNearBaseline = 0
        pendingMeasurement = nil
        framesSinceLastReadyDiag = 0
    }

    // MARK: - Continuous depth signal (display only — world coords OK here)

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

    private func handleIdle(pose: PoseResult, noseY: CGFloat, worldY: Float?, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?) -> RepUpdate {
        if pose.isPostureReadyForRepCounting {
            readyPoseStreak += 1
            if readyPoseStreak >= framesRequiredForReadyLock {
                baselineNoseY = noseY
                baselineWorldY = worldY
                baselineShoulderMidY = shoulderMidY
                baselineWristMidY = wristMidY
                baselineHipMidY = hipMidY
                currentPhase = .ready
                readyPoseStreak = 0

                let msg = formatLockLog(noseY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY)
                return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: msg)
            }
            return RepUpdate(
                phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil,
                debugMessage: "Hold plank to lock start position (\(readyPoseStreak)/\(framesRequiredForReadyLock))"
            )
        }
        readyPoseStreak = 0
        return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil,
                         debugMessage: "Waiting for landmarks, distance & plank angle")
    }

    // MARK: - Ready: descent detection (ALL gates use screen-space coordinates)

    private func handleReady(noseY: CGFloat, worldY: Float?, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, timestamp: TimeInterval) -> RepUpdate {
        guard let baseline = baselineNoseY else {
            currentPhase = .idle
            return RepUpdate(phase: .idle, repCount: repCount, noseY: noseY, depthPercent: nil, debugMessage: nil)
        }

        let noseDelta = noseY - baseline
        let noseDown = noseDelta > downThresholdFraction

        let relativeGap: CGFloat
        if let smY = shoulderMidY, let bsY = baselineShoulderMidY {
            relativeGap = noseDelta - (smY - bsY)
        } else {
            relativeGap = noseDelta
        }
        let relGatePass = relativeGap > minimumRelativeGapForDescent

        let wristAnchored: Bool
        if let wmY = wristMidY, let bwY = baselineWristMidY {
            wristAnchored = abs(wmY - bwY) < maxWristDrift
        } else {
            wristAnchored = true
        }

        let hipAnchored: Bool
        if let hmY = hipMidY, let bhY = baselineHipMidY {
            hipAnchored = abs(hmY - bhY) < maxHipDrift
        } else {
            hipAnchored = true
        }

        let isGoingDown = noseDown && relGatePass && wristAnchored && hipAnchored

        if isGoingDown {
            framesSinceLastReadyDiag = 0
            if confirmTransition(to: .down) {
                currentPhase = .down
                peakNoseY = noseY
                peakShoulderMidY = shoulderMidY ?? 0
                minWorldYThisRep = worldY ?? .greatestFiniteMagnitude
                maxWorldYThisRep = baselineWorldY ?? -.greatestFiniteMagnitude
                currentRepStartTime = timestamp
                leftShoulderYsThisRep = []
                rightShoulderYsThisRep = []
                leftShoulderWorldYsThisRep = []
                rightShoulderWorldYsThisRep = []

                let msg = formatDownLog(noseY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY)
                return RepUpdate(phase: .down, repCount: repCount, noseY: noseY,
                                 depthPercent: depthPercent(noseY, worldY: worldY), debugMessage: msg)
            }
        } else {
            resetCandidate()
        }

        // Near-miss diagnostic: log when nose is moving but not enough for threshold
        framesSinceLastReadyDiag += 1
        let nearMissThreshold: CGFloat = 0.03
        if noseDelta > nearMissThreshold && !isGoingDown && framesSinceLastReadyDiag >= readyDiagInterval {
            framesSinceLastReadyDiag = 0
            var failedGates: [String] = []
            if !noseDown { failedGates.append("Δnose=\(f(noseDelta))<\(f(downThresholdFraction))") }
            if !relGatePass { failedGates.append("Δrel=\(f(relativeGap))<\(f(minimumRelativeGapForDescent))") }
            if !wristAnchored { failedGates.append("wDrift>\(f(maxWristDrift))") }
            if !hipAnchored { failedGates.append("hDrift>\(f(maxHipDrift))") }
            let gateStr = failedGates.joined(separator: ", ")
            let msg = "NEAR-MISS | nose=\(f(noseY)) Δnose=\(f(noseDelta)) Δrel=\(f(relativeGap)) | blocked by: \(gateStr) — try moving closer to phone"
            return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: msg)
        }

        return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: nil)
    }

    // MARK: - Down: return detection + gate validation (screen-space only)

    private func handleDown(noseY: CGFloat, worldY: Float?, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, timestamp: TimeInterval) -> RepUpdate {
        guard let baseline = baselineNoseY else {
            return RepUpdate(phase: currentPhase, repCount: repCount, noseY: noseY, depthPercent: nil, debugMessage: nil)
        }

        peakNoseY = max(peakNoseY, noseY)
        if let smY = shoulderMidY {
            peakShoulderMidY = max(peakShoulderMidY, smY)
        }
        if let wy = worldY {
            minWorldYThisRep = min(minWorldYThisRep, wy)
            maxWorldYThisRep = max(maxWorldYThisRep, wy)
        }

        let noseReturnDelta = peakNoseY - noseY
        let isComingUp = noseReturnDelta > upThresholdFraction

        if isComingUp {
            if confirmTransition(to: .ascending) {
                // Gate 1: minimum depth (screen-space only)
                let peakDepth = (peakNoseY - baseline) >= minimumDepthGate
                guard peakDepth else {
                    let msg = formatRejectLog(reason: "shallow", noseY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, duration: timestamp - currentRepStartTime)
                    resetCandidate()
                    currentPhase = .ready
                    updateBaselines(noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, wristMidY: wristMidY, hipMidY: hipMidY)
                    return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: msg)
                }

                // Gate 2: minimum duration
                let duration = timestamp - currentRepStartTime
                guard duration >= minimumRepDuration else {
                    let msg = formatRejectLog(reason: "too fast \(String(format: "%.2fs", duration))", noseY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, duration: duration)
                    resetCandidate()
                    currentPhase = .ready
                    updateBaselines(noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, wristMidY: wristMidY, hipMidY: hipMidY)
                    return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: msg)
                }

                // Gate 3: maximum duration
                guard duration <= maximumRepDuration else {
                    let msg = formatRejectLog(reason: "too slow \(String(format: "%.1fs", duration))", noseY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, duration: duration)
                    resetCandidate()
                    currentPhase = .ready
                    updateBaselines(noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, wristMidY: wristMidY, hipMidY: hipMidY)
                    return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: msg)
                }

                // All gates pass — store candidate and enter ascending
                pendingMeasurement = RepMeasurement(
                    minNoseY: peakNoseY,
                    maxNoseY: baseline,
                    minWorldY: minWorldYThisRep == .greatestFiniteMagnitude ? nil : minWorldYThisRep,
                    maxWorldY: maxWorldYThisRep == -.greatestFiniteMagnitude ? nil : maxWorldYThisRep,
                    durationSeconds: duration,
                    leftShoulderYs: leftShoulderYsThisRep,
                    rightShoulderYs: rightShoulderYsThisRep,
                    leftShoulderWorldYs: leftShoulderWorldYsThisRep,
                    rightShoulderWorldYs: rightShoulderWorldYsThisRep
                )
                currentPhase = .ascending
                ascendingStartTime = timestamp
                framesNearBaseline = 0

                let msg = formatAscendingLog(noseY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, duration: duration)
                return RepUpdate(phase: .ascending, repCount: repCount, noseY: noseY,
                                 depthPercent: depthPercent(noseY, worldY: worldY), debugMessage: msg)
            }
        } else {
            resetCandidate()
        }

        return RepUpdate(phase: .down, repCount: repCount, noseY: noseY,
                         depthPercent: depthPercent(noseY, worldY: worldY), debugMessage: nil)
    }

    // MARK: - Ascending: return-to-top confirmation

    private func handleAscending(noseY: CGFloat, worldY: Float?, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, timestamp: TimeInterval) -> RepUpdate {
        guard let bNose = baselineNoseY else {
            currentPhase = .ready
            return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: nil)
        }

        // Timeout — body never returned to top
        if timestamp - ascendingStartTime > ascendingTimeoutSeconds {
            let msg = "TIMEOUT (\(String(format: "%.1fs", timestamp - ascendingStartTime)) in ascending) — return to top not confirmed"
            pendingMeasurement = nil
            currentPhase = .ready
            updateBaselines(noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, wristMidY: wristMidY, hipMidY: hipMidY)
            return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: msg)
        }

        // Check return-to-baseline conditions
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
                guard let measurement = pendingMeasurement else {
                    currentPhase = .ready
                    return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: nil)
                }
                completedReps.append(measurement)
                repCount += 1
                pendingMeasurement = nil

                calibrateIfNeeded()

                let msg = formatRepLog(repNumber: repCount, noseY: noseY, shoulderMidY: shoulderMidY, hipMidY: hipMidY, wristMidY: wristMidY, duration: measurement.durationSeconds)

                resetRepTracking()
                updateBaselines(noseY: noseY, worldY: worldY, shoulderMidY: shoulderMidY, wristMidY: wristMidY, hipMidY: hipMidY)
                currentPhase = .ready
                return RepUpdate(phase: .ready, repCount: repCount, noseY: noseY, depthPercent: 0, debugMessage: msg)
            }
        } else {
            framesNearBaseline = 0
        }

        return RepUpdate(phase: .ascending, repCount: repCount, noseY: noseY,
                         depthPercent: depthPercent(noseY, worldY: worldY), debugMessage: nil)
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

    private func computeShoulderMidY(from pose: PoseResult) -> CGFloat? {
        guard let ls = pose.landmark(.leftShoulder), let rs = pose.landmark(.rightShoulder),
              ls.confidence >= 0.3, rs.confidence >= 0.3 else { return nil }
        return (ls.position.y + rs.position.y) * 0.5
    }

    private func computeHipMidY(from pose: PoseResult) -> CGFloat? {
        guard let lh = pose.landmark(.leftHip), let rh = pose.landmark(.rightHip),
              lh.confidence >= 0.2, rh.confidence >= 0.2 else { return nil }
        return (lh.position.y + rh.position.y) * 0.5
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

    private func updateBaselines(noseY: CGFloat, worldY: Float?, shoulderMidY: CGFloat?, wristMidY: CGFloat?, hipMidY: CGFloat?) {
        baselineNoseY = noseY
        baselineWorldY = worldY
        baselineShoulderMidY = shoulderMidY
        baselineWristMidY = wristMidY
        baselineHipMidY = hipMidY
    }

    private func resetRepTracking() {
        peakNoseY = 0.0
        peakShoulderMidY = 0.0
        minWorldYThisRep = .greatestFiniteMagnitude
        maxWorldYThisRep = -.greatestFiniteMagnitude
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

    // MARK: - Diagnostic log formatters

    private func f(_ v: CGFloat) -> String { String(format: "%.3f", v) }
    private func fo(_ v: CGFloat?) -> String { v.map { f($0) } ?? "n/a" }

    private func driftStr(current: CGFloat?, baseline: CGFloat?) -> String {
        guard let c = current, let b = baseline else { return "n/a" }
        return f(abs(c - b))
    }

    private func formatLockLog(noseY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?) -> String {
        let relGap = shoulderMidY.map { noseY - $0 }
        return "LOCKED | nose=\(f(noseY)) shldr=\(fo(shoulderMidY)) hip=\(fo(hipMidY)) wrist=\(fo(wristMidY)) rel=\(fo(relGap))"
    }

    private func formatDownLog(noseY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?) -> String {
        let dn = baselineNoseY.map { noseY - $0 }
        let ds = (shoulderMidY != nil && baselineShoulderMidY != nil) ? shoulderMidY! - baselineShoulderMidY! : nil as CGFloat?
        let dr = (dn != nil && ds != nil) ? dn! - ds! : nil as CGFloat?
        return "DOWN | nose=\(f(noseY)) shldr=\(fo(shoulderMidY)) hip=\(fo(hipMidY)) wrist=\(fo(wristMidY)) | Δnose=\(fo(dn)) Δshldr=\(fo(ds)) Δrel=\(fo(dr)) wDrift=\(driftStr(current: wristMidY, baseline: baselineWristMidY)) hDrift=\(driftStr(current: hipMidY, baseline: baselineHipMidY))"
    }

    private func formatAscendingLog(noseY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, duration: TimeInterval) -> String {
        let dn = baselineNoseY.map { peakNoseY - $0 }
        let ds = baselineShoulderMidY.map { peakShoulderMidY - $0 }
        let dr = (dn != nil && ds != nil) ? dn! - ds! : nil as CGFloat?
        return "ASCENDING dur=\(String(format: "%.2fs", duration)) | nose=\(f(noseY)) shldr=\(fo(shoulderMidY)) hip=\(fo(hipMidY)) wrist=\(fo(wristMidY)) | Δnose=\(fo(dn)) Δshldr=\(fo(ds)) Δrel=\(fo(dr)) wDrift=\(driftStr(current: wristMidY, baseline: baselineWristMidY)) hDrift=\(driftStr(current: hipMidY, baseline: baselineHipMidY)) | peak: nose=\(f(peakNoseY)) shldr=\(f(peakShoulderMidY))"
    }

    private func formatRepLog(repNumber: Int, noseY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, duration: TimeInterval) -> String {
        let dn = baselineNoseY.map { peakNoseY - $0 }
        let ds = baselineShoulderMidY.map { peakShoulderMidY - $0 }
        let dr = (dn != nil && ds != nil) ? dn! - ds! : nil as CGFloat?
        return "REP #\(repNumber) dur=\(String(format: "%.2fs", duration)) | nose=\(f(noseY)) shldr=\(fo(shoulderMidY)) hip=\(fo(hipMidY)) wrist=\(fo(wristMidY)) | Δnose=\(fo(dn)) Δshldr=\(fo(ds)) Δrel=\(fo(dr)) wDrift=\(driftStr(current: wristMidY, baseline: baselineWristMidY)) hDrift=\(driftStr(current: hipMidY, baseline: baselineHipMidY)) | peak: nose=\(f(peakNoseY)) shldr=\(f(peakShoulderMidY))"
    }

    private func formatRejectLog(reason: String, noseY: CGFloat, shoulderMidY: CGFloat?, hipMidY: CGFloat?, wristMidY: CGFloat?, duration: TimeInterval) -> String {
        let dn = baselineNoseY.map { peakNoseY - $0 }
        let ds = baselineShoulderMidY.map { peakShoulderMidY - $0 }
        let dr = (dn != nil && ds != nil) ? dn! - ds! : nil as CGFloat?
        return "REJECTED (\(reason)) dur=\(String(format: "%.2fs", duration)) | nose=\(f(noseY)) shldr=\(fo(shoulderMidY)) hip=\(fo(hipMidY)) wrist=\(fo(wristMidY)) | Δnose=\(fo(dn)) Δshldr=\(fo(ds)) Δrel=\(fo(dr)) wDrift=\(driftStr(current: wristMidY, baseline: baselineWristMidY)) hDrift=\(driftStr(current: hipMidY, baseline: baselineHipMidY))"
    }
}
