import XCTest
@testable import EngineCore

final class PoseTrackingGateTests: XCTestCase {

    var gate: PoseTrackingGate!

    override func setUp() {
        super.setUp()
        gate = PoseTrackingGate()
    }

    // MARK: - Initial State

    func testInitialStateIsLost() {
        XCTAssertEqual(gate.currentState, .lost)
    }

    // MARK: - No Pose

    func testNilPoseStaysLost() {
        let result = gate.update(pose: nil)
        XCTAssertEqual(result.state, .lost)
        XCTAssertNil(result.poseForRepCounting)
        XCTAssertFalse(result.coachingMessage.isEmpty, "Should show coaching when lost")
    }

    // MARK: - Lost → LiningUp → Locked

    func testBodyDetectedTransitionsToLiningUp() {
        let pose = SyntheticPose.pushupPose(noseY: 0.30)
        let result = gate.update(pose: pose)
        XCTAssertEqual(result.state, .liningUp)
    }

    func testLocksAfterSufficientStableFrames() {
        // Nose stability needs 5 samples, then 10 good-frame streak = 14 total frames (0-indexed: 0..13)
        for i in 0..<13 {
            let result = gate.update(pose: SyntheticPose.pushupPose(noseY: 0.30, timestamp: Double(i) * 0.1))
            XCTAssertNotEqual(result.state, .locked, "Frame \(i): should not be locked yet")
        }
        let result = gate.update(pose: SyntheticPose.pushupPose(noseY: 0.30, timestamp: 1.3))
        XCTAssertEqual(result.state, .locked, "Frame 13 (14th frame) should lock")
        XCTAssertNotNil(result.poseForRepCounting)
    }

    func testUnstableNosePreventsLock() {
        for i in 0..<30 {
            // Alternating nose Y with large jumps prevents nose stability
            let noseY: CGFloat = (i % 2 == 0) ? 0.20 : 0.50
            let result = gate.update(pose: SyntheticPose.pushupPose(noseY: noseY, timestamp: Double(i) * 0.1))
            XCTAssertNotEqual(result.state, .locked, "Unstable nose: frame \(i) should not lock")
        }
    }

    // MARK: - Locked Behavior (sticky)

    func testLockedStaysLockedWithValidPose() {
        lockGate()

        for _ in 0..<10 {
            let result = gate.update(pose: SyntheticPose.pushupPose(noseY: 0.30))
            XCTAssertEqual(result.state, .locked)
            XCTAssertNotNil(result.poseForRepCounting)
        }
    }

    func testLockedSurvivesBriefPoseLoss() {
        lockGate()

        // Lose pose for 5 frames (well under 30-frame drop threshold)
        for _ in 0..<5 {
            let result = gate.update(pose: nil)
            XCTAssertEqual(result.state, .locked, "Brief loss should stay locked")
            XCTAssertNil(result.poseForRepCounting, "No pose available during loss")
        }

        // Pose returns
        let result = gate.update(pose: SyntheticPose.pushupPose(noseY: 0.30))
        XCTAssertEqual(result.state, .locked)
        XCTAssertNotNil(result.poseForRepCounting)
    }

    func testLockedDropsToLostAfter30FrameLoss() {
        lockGate()

        // 29 frames without pose → still locked
        for i in 0..<29 {
            let result = gate.update(pose: nil)
            XCTAssertEqual(result.state, .locked, "Frame \(i): should still be locked")
        }

        // 30th frame → drops to lost
        let result = gate.update(pose: nil)
        XCTAssertEqual(result.state, .lost, "30th consecutive nil frame should drop to lost")
    }

    // MARK: - Reset

    func testResetClearsToLost() {
        lockGate()
        XCTAssertEqual(gate.currentState, .locked)

        gate.reset()
        XCTAssertEqual(gate.currentState, .lost)
    }

    func testResetRequiresRelockingFromScratch() {
        lockGate()
        gate.reset()

        // Single valid frame should not re-lock immediately
        let result = gate.update(pose: SyntheticPose.pushupPose(noseY: 0.30))
        XCTAssertNotEqual(result.state, .locked, "Should need full lock sequence after reset")
    }

    // MARK: - Helpers

    /// Feed enough stable frames to transition from lost → locked.
    private func lockGate() {
        for i in 0..<15 {
            _ = gate.update(pose: SyntheticPose.pushupPose(noseY: 0.30, timestamp: Double(i) * 0.1))
        }
        XCTAssertEqual(gate.currentState, .locked, "lockGate helper should leave gate locked")
    }
}
