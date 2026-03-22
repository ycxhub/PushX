import XCTest
@testable import EngineCore

final class RepCountingEngineTests: XCTestCase {

    var engine: RepCountingEngine!

    override func setUp() {
        super.setUp()
        engine = RepCountingEngine()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertEqual(engine.currentPhase, .idle)
        XCTAssertEqual(engine.repCount, 0)
        XCTAssertTrue(engine.completedReps.isEmpty)
    }

    // MARK: - Nil / Weak Pose

    func testNilPoseFromIdleStaysIdle() {
        let update = engine.update(with: nil)
        XCTAssertEqual(update.phase, .idle)
        XCTAssertEqual(update.repCount, 0)
    }

    func testLowConfidencePoseTreatedAsLost() {
        let weak = SyntheticPose.pushupPose(confidence: 0.1)
        let update = engine.update(with: weak)
        XCTAssertEqual(update.phase, .idle)
        XCTAssertEqual(update.repCount, 0)
    }

    // MARK: - Idle → Ready (baseline lock)

    func testIdleToReadyRequires30StableFrames() {
        for i in 0..<29 {
            let pose = SyntheticPose.pushupPose(noseY: 0.48, timestamp: Double(i) * 0.04)
            let update = engine.update(with: pose)
            XCTAssertEqual(update.phase, .idle, "Frame \(i): should still be idle")
        }

        let pose = SyntheticPose.pushupPose(noseY: 0.48, timestamp: 1.16)
        let update = engine.update(with: pose)
        XCTAssertEqual(update.phase, .ready, "30th frame should transition to ready")
        XCTAssertEqual(engine.repCount, 0)
    }

    func testStandingPoseDoesNotArmEngine() {
        for i in 0..<40 {
            let pose = SyntheticPose.standingPose(timestamp: Double(i) * 0.04)
            _ = engine.update(with: pose)
        }
        XCTAssertEqual(engine.currentPhase, .idle, "Standing pose should never transition to ready")
    }

    // MARK: - Full Rep Cycle

    func testFullRepCycleCountsOneRep() {
        armEngine(baselineNoseY: 0.48)
        XCTAssertEqual(engine.currentPhase, .ready)

        // Descent: nose=0.62 (Δ=0.14), shoulder=0.50 (Δ=0.08), Δrel=0.06, wrists anchored
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .down)

        // Return: 6 frames to confirm ascending + 4 frames to confirm return-to-top
        for i in 0..<10 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.49, shoulderY: 0.42, wristY: 0.42, timestamp: 3.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.repCount, 1)
        XCTAssertEqual(engine.currentPhase, .ready)
        XCTAssertEqual(engine.completedReps.count, 1)
    }

    func testMultipleRepsCountCorrectly() {
        armEngine(baselineNoseY: 0.48)

        for rep in 1...5 {
            let t = Double(rep) * 3.0
            for i in 0..<6 {
                _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: t + Double(i) * 0.04))
            }
            for i in 0..<10 {
                _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.49, shoulderY: 0.42, wristY: 0.42, timestamp: t + 1.0 + Double(i) * 0.04))
            }
            XCTAssertEqual(engine.repCount, rep, "After rep \(rep)")
        }
        XCTAssertEqual(engine.completedReps.count, 5)
    }

    // MARK: - Hysteresis

    func testSmallJitterDoesNotTriggerRep() {
        armEngine(baselineNoseY: 0.48)

        for i in 0..<20 {
            let jitter: CGFloat = (i % 2 == 0) ? 0.03 : -0.03
            let pose = SyntheticPose.pushupPose(noseY: 0.48 + jitter, timestamp: 2.0 + Double(i) * 0.04)
            _ = engine.update(with: pose)
        }

        XCTAssertEqual(engine.repCount, 0, "Small jitter should not count reps")
    }

    func testPartialDescentNoRep() {
        armEngine(baselineNoseY: 0.48)

        // Nose delta 0.07 < downThreshold 0.10 → DOWN never entered
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.55, timestamp: 2.0 + Double(i) * 0.04))
        }
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.48, timestamp: 3.0 + Double(i) * 0.04))
        }

        XCTAssertEqual(engine.repCount, 0, "Movement below threshold should not count")
    }

    func testShallowRepRejectedByDepthGate() {
        armEngine(baselineNoseY: 0.48)
        XCTAssertEqual(engine.repCount, 0, "No reps should be counted yet")
    }

    // MARK: - Descent Gates (Delta_rel + Wrist Anchor)

    func testDeltaRelGateRejectsSway() {
        armEngine(baselineNoseY: 0.48)

        // Sway: nose and shoulders both move +0.12. Delta_rel = 0.12 - 0.12 = 0.00 < 0.02
        for i in 0..<8 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.60, shoulderY: 0.54, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }
        XCTAssertNotEqual(engine.currentPhase, .down, "Equal nose/shoulder displacement (sway) should not enter DOWN")
        XCTAssertEqual(engine.repCount, 0)
    }

    func testDeltaRelGateAcceptsRealPushup() {
        armEngine(baselineNoseY: 0.48)

        // Real pushup: nose Δ=0.14, shoulder Δ=0.08 → Delta_rel=0.06 > 0.02
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .down, "Real pushup descent should enter DOWN")

        for i in 0..<10 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.49, shoulderY: 0.42, wristY: 0.42, timestamp: 3.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.repCount, 1, "Real pushup should count after return confirmed")
    }

    func testWristDriftRejectsWholeBodyTranslation() {
        armEngine(baselineNoseY: 0.48)

        // Delta_rel OK (0.06>0.02), but wrists also shift: drift=|0.52-0.42|=0.10>0.05
        for i in 0..<8 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.52, timestamp: 2.0 + Double(i) * 0.04))
        }
        XCTAssertNotEqual(engine.currentPhase, .down, "Wrist drift > 0.05 should prevent DOWN entry")
        XCTAssertEqual(engine.repCount, 0)
    }

    func testHipDriftRejectsKneelingDescent() {
        armEngine(baselineNoseY: 0.48)

        // Nose/shoulder/wrist look like a real pushup, but hips shift: drift=|0.58-0.48|=0.10>0.08
        for i in 0..<8 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, hipY: 0.58, timestamp: 2.0 + Double(i) * 0.04))
        }
        XCTAssertNotEqual(engine.currentPhase, .down, "Hip drift > 0.08 should prevent DOWN entry (kneeling detected)")
        XCTAssertEqual(engine.repCount, 0)
    }

    func testForwardSwayDoesNotTriggerRep() {
        armEngine(baselineNoseY: 0.48)

        // Larger forward sway: nose Δ=0.12, shoulder Δ=0.12 → Delta_rel=0.00 < 0.02
        for i in 0..<8 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.60, shoulderY: 0.54, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }
        // Sway back
        for i in 0..<8 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.48, shoulderY: 0.42, wristY: 0.42, timestamp: 3.0 + Double(i) * 0.04))
        }

        XCTAssertEqual(engine.repCount, 0, "Forward/backward sway should not count as a rep")
    }

    // MARK: - Minimum Rep Duration Gate

    func testShortDurationRepRejected() {
        armEngine(baselineNoseY: 0.48)

        // Valid descent
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .down)

        // Return too quickly: 6 frames at 0.04s each → t=2.24..2.44, duration=0.24s < 0.35s
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.49, shoulderY: 0.42, wristY: 0.42, timestamp: 2.24 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.repCount, 0, "Rep completed in ~0.24s should be rejected (minimum 0.35s)")
        XCTAssertEqual(engine.currentPhase, .ready, "Engine should return to ready after rejection")
    }

    // MARK: - Maximum Rep Duration Gate

    func testVeryLongRepRejected() {
        armEngine(baselineNoseY: 0.48)

        // Valid descent
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .down)

        // Stay at bottom for 9+ seconds, then return (exceeds 8s max)
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.49, shoulderY: 0.42, wristY: 0.42, timestamp: 12.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.repCount, 0, "Rep with duration > 8s should be rejected")
        XCTAssertEqual(engine.currentPhase, .ready, "Engine should return to ready after max-duration rejection")
    }

    // MARK: - Ascending Phase (Return-to-Top Confirmation)

    func testAscendingPhaseRequiresReturnToBaseline() {
        armEngine(baselineNoseY: 0.48)

        // Valid descent
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .down)

        // Partial return to 0.55 — far enough from peak (0.07>0.05) to signal return
        // but NOT near baseline (|0.55-0.48|=0.07>0.06 tolerance)
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.55, shoulderY: 0.42, wristY: 0.42, timestamp: 3.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .ascending, "Should enter ascending after valid return signal")

        // Stay at 0.55 for more frames — still not near baseline
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.55, shoulderY: 0.42, wristY: 0.42, timestamp: 3.24 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .ascending, "Should remain in ascending — not near baseline")
        XCTAssertEqual(engine.repCount, 0, "Rep should not count until return confirmed")
    }

    func testAscendingPhaseCountsAfterConfirmedReturn() {
        armEngine(baselineNoseY: 0.48)

        // Valid descent
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .down)

        // Return signal → ascending (at t=3.20)
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.49, shoulderY: 0.42, wristY: 0.42, timestamp: 3.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .ascending)

        // 3 frames near baseline — not enough yet
        for i in 0..<3 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.49, shoulderY: 0.42, wristY: 0.42, timestamp: 3.24 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.repCount, 0, "3 frames near baseline should not count yet")
        XCTAssertEqual(engine.currentPhase, .ascending)

        // 4th frame near baseline → count!
        _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.49, shoulderY: 0.42, wristY: 0.42, timestamp: 3.36))
        XCTAssertEqual(engine.repCount, 1, "4th frame near baseline should count the rep")
        XCTAssertEqual(engine.currentPhase, .ready)
    }

    func testAscendingTimeoutDoesNotCount() {
        armEngine(baselineNoseY: 0.48)

        // Valid descent
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }

        // Partial return → ascending (at t=3.20, ascendingStartTime=3.20)
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.55, shoulderY: 0.42, wristY: 0.42, timestamp: 3.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .ascending)

        // Feed a frame after 5s timeout (9.0 - 3.20 = 5.8s > 5.0s)
        _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.55, shoulderY: 0.42, wristY: 0.42, timestamp: 9.0))
        XCTAssertEqual(engine.currentPhase, .ready, "Should timeout and return to ready")
        XCTAssertEqual(engine.repCount, 0, "Timeout should not count the rep")
    }

    // MARK: - Pause / Resume

    func testPauseAfterPoseLostFor15Frames() {
        armEngine(baselineNoseY: 0.48)

        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .down)

        for _ in 0..<14 {
            _ = engine.update(with: nil)
        }
        XCTAssertNotEqual(engine.currentPhase, .paused, "14 frames without pose should not pause yet")

        _ = engine.update(with: nil)
        XCTAssertEqual(engine.currentPhase, .paused)
    }

    func testResumeFromPausePreservesPhaseAndCount() {
        armEngine(baselineNoseY: 0.48)

        // First full rep
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }
        for i in 0..<10 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.49, shoulderY: 0.42, wristY: 0.42, timestamp: 3.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.repCount, 1)

        // Second rep descent
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 5.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .down)

        // Lose pose → pause
        for _ in 0..<16 {
            _ = engine.update(with: nil)
        }
        XCTAssertEqual(engine.currentPhase, .paused)

        // Resume
        let update = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 7.0))
        XCTAssertEqual(update.phase, .down, "Should resume to pre-pause phase")
        XCTAssertEqual(engine.repCount, 1, "Rep count preserved through pause")
    }

    // MARK: - Depth Tracking

    func testContinuousDepthPercentIncreasesWithDepth() {
        armEngine(baselineNoseY: 0.48)

        let shallow = SyntheticPose.pushupPose(noseY: 0.52, timestamp: 2.0)
        let shallowDepth = engine.continuousDepthPercent(pose: shallow)

        let deep = SyntheticPose.pushupPose(noseY: 0.62, timestamp: 2.04)
        let deepDepth = engine.continuousDepthPercent(pose: deep)

        XCTAssertGreaterThan(deepDepth, shallowDepth)
        XCTAssertGreaterThan(deepDepth, 0)
        XCTAssertLessThanOrEqual(deepDepth, 1.0)
    }

    // MARK: - Rep Measurement Recording

    func testRepMeasurementRecordsDuration() {
        armEngine(baselineNoseY: 0.48)

        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }
        for i in 0..<10 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.49, shoulderY: 0.42, wristY: 0.42, timestamp: 4.0 + Double(i) * 0.04))
        }

        XCTAssertEqual(engine.completedReps.count, 1)
        let measurement = engine.completedReps[0]
        XCTAssertGreaterThan(measurement.durationSeconds, 0)
    }

    // MARK: - Reset

    func testResetClearsAllState() {
        armEngine(baselineNoseY: 0.48)
        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }
        for i in 0..<10 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.49, shoulderY: 0.42, wristY: 0.42, timestamp: 3.0 + Double(i) * 0.04))
        }
        XCTAssertEqual(engine.repCount, 1)

        engine.reset()

        XCTAssertEqual(engine.repCount, 0)
        XCTAssertEqual(engine.currentPhase, .idle)
        XCTAssertTrue(engine.completedReps.isEmpty)
    }

    // MARK: - Plank Detection Properties

    func testPlankDetectionReturnsTrueForPushupPose() {
        let plank = SyntheticPose.pushupPose()
        XCTAssertTrue(plank.isInPlankFromFrontCamera, "Pushup pose should be detected as plank")
        XCTAssertFalse(plank.isStandingPose, "Pushup pose should not be detected as standing")
    }

    func testPlankDetectionReturnsFalseForStandingPose() {
        let standing = SyntheticPose.standingPose()
        XCTAssertFalse(standing.isInPlankFromFrontCamera, "Standing pose should not be detected as plank")
        XCTAssertTrue(standing.isStandingPose, "Standing pose should be detected as standing")
    }

    func testPostureReadyRequiresPlankNotStanding() {
        let plank = SyntheticPose.pushupPose()
        XCTAssertTrue(plank.isPostureReadyForRepCounting, "Plank with good calibration should be ready")

        let standing = SyntheticPose.standingPose()
        XCTAssertFalse(standing.isPostureReadyForRepCounting, "Standing should not be ready for rep counting")
    }

    // MARK: - Diagnostic Logging

    func testDiagnosticLogIncludesJointCoordinatesOnLock() {
        var lastDebug: String?
        for i in 0..<31 {
            let p = SyntheticPose.pushupPose(noseY: 0.48, shoulderY: 0.42, timestamp: Double(i) * 0.04)
            let update = engine.update(with: p)
            lastDebug = update.debugMessage ?? lastDebug
        }
        XCTAssertEqual(engine.currentPhase, .ready)
        XCTAssertNotNil(lastDebug)
        XCTAssertTrue(lastDebug!.contains("LOCKED"), "Lock message should contain LOCKED prefix")
        XCTAssertTrue(lastDebug!.contains("nose="), "Lock message should include nose coordinate")
        XCTAssertTrue(lastDebug!.contains("shldr="), "Lock message should include shoulder coordinate")
        XCTAssertTrue(lastDebug!.contains("wrist="), "Lock message should include wrist coordinate")
    }

    func testDiagnosticLogIncludesJointCoordinatesOnRepCounted() {
        armEngine(baselineNoseY: 0.48)

        for i in 0..<6 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: 0.62, shoulderY: 0.50, wristY: 0.42, timestamp: 2.0 + Double(i) * 0.04))
        }

        var repDebug: String?
        for i in 0..<10 {
            let update = engine.update(with: SyntheticPose.pushupPose(noseY: 0.49, shoulderY: 0.42, wristY: 0.42, timestamp: 3.0 + Double(i) * 0.04))
            if let msg = update.debugMessage, msg.contains("REP #") {
                repDebug = msg
            }
        }
        XCTAssertEqual(engine.repCount, 1)
        XCTAssertNotNil(repDebug, "Rep counted should produce a diagnostic message")
        XCTAssertTrue(repDebug!.contains("dur="), "Rep log should include duration")
        XCTAssertTrue(repDebug!.contains("Δnose="), "Rep log should include nose delta")
        XCTAssertTrue(repDebug!.contains("Δshldr="), "Rep log should include shoulder delta")
        XCTAssertTrue(repDebug!.contains("wDrift="), "Rep log should include wrist drift")
        XCTAssertTrue(repDebug!.contains("peak:"), "Rep log should include peak values")
    }

    // MARK: - Helpers

    private func armEngine(baselineNoseY: CGFloat) {
        for i in 0..<31 {
            _ = engine.update(with: SyntheticPose.pushupPose(noseY: baselineNoseY, timestamp: Double(i) * 0.04))
        }
        XCTAssertEqual(engine.currentPhase, .ready, "armEngine should leave engine in ready phase")
    }
}
