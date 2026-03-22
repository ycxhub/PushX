import XCTest
@testable import EngineCore

final class FormScoringEngineTests: XCTestCase {

    var engine: FormScoringEngine!

    override func setUp() {
        super.setUp()
        engine = FormScoringEngine()
    }

    // MARK: - Minimum Reps Requirement

    func testReturnsNilForZeroReps() {
        XCTAssertNil(engine.computeScores(from: []))
    }

    func testReturnsNilForOneRep() {
        let reps = [makeRep(minNoseY: 0.42, maxNoseY: 0.30, duration: 2.0)]
        XCTAssertNil(engine.computeScores(from: reps))
    }

    func testReturnsSomethingForTwoReps() {
        let reps = [
            makeRep(minNoseY: 0.42, maxNoseY: 0.30, duration: 2.0),
            makeRep(minNoseY: 0.42, maxNoseY: 0.30, duration: 2.0),
        ]
        XCTAssertNotNil(engine.computeScores(from: reps))
    }

    // MARK: - Depth Score

    func testConsistentDepthScoresHigh() {
        let reps = (0..<5).map { _ in
            makeRep(minNoseY: 0.42, maxNoseY: 0.30, duration: 2.0)
        }
        let scores = engine.computeScores(from: reps)!
        XCTAssertGreaterThanOrEqual(scores.depth, 95, "Identical depths should score near 100")
    }

    func testShallowRepsScoreLowerDepth() {
        let reps = [
            makeRep(minNoseY: 0.42, maxNoseY: 0.30, duration: 2.0),
            makeRep(minNoseY: 0.42, maxNoseY: 0.30, duration: 2.0),
            makeRep(minNoseY: 0.33, maxNoseY: 0.30, duration: 2.0),
            makeRep(minNoseY: 0.33, maxNoseY: 0.30, duration: 2.0),
        ]
        let scores = engine.computeScores(from: reps)!
        XCTAssertLessThan(scores.depth, 90, "Mix of deep and shallow reps should reduce depth score")
    }

    // MARK: - Alignment Score

    func testSymmetricShouldersScoreHigh() {
        let reps = (0..<5).map { _ in
            makeRep(
                minNoseY: 0.42, maxNoseY: 0.30, duration: 2.0,
                leftShoulderYs: [0.45, 0.45, 0.45],
                rightShoulderYs: [0.45, 0.45, 0.45]
            )
        }
        let scores = engine.computeScores(from: reps)!
        XCTAssertGreaterThanOrEqual(scores.alignment, 95, "Perfectly symmetric shoulders → high alignment")
    }

    func testAsymmetricShouldersScoreLow() {
        let reps = (0..<5).map { _ in
            makeRep(
                minNoseY: 0.42, maxNoseY: 0.30, duration: 2.0,
                leftShoulderYs: [0.40, 0.40, 0.40],
                rightShoulderYs: [0.55, 0.55, 0.55]
            )
        }
        let scores = engine.computeScores(from: reps)!
        XCTAssertLessThanOrEqual(scores.alignment, 10, "Large shoulder asymmetry → very low alignment")
    }

    // MARK: - Consistency Score

    func testUniformRepsScoreHighConsistency() {
        let reps = (0..<5).map { _ in
            makeRep(minNoseY: 0.42, maxNoseY: 0.30, duration: 2.0)
        }
        let scores = engine.computeScores(from: reps)!
        XCTAssertGreaterThanOrEqual(scores.consistency, 95, "Identical reps → high consistency")
    }

    func testVariedRepsScoreLowConsistency() {
        let reps = [
            makeRep(minNoseY: 0.42, maxNoseY: 0.30, duration: 1.0),
            makeRep(minNoseY: 0.50, maxNoseY: 0.30, duration: 4.0),
            makeRep(minNoseY: 0.35, maxNoseY: 0.30, duration: 0.5),
            makeRep(minNoseY: 0.48, maxNoseY: 0.30, duration: 3.5),
        ]
        let scores = engine.computeScores(from: reps)!
        XCTAssertLessThan(scores.consistency, 70, "Widely varying reps → low consistency")
    }

    // MARK: - Composite Weighting

    func testCompositeIs40Depth30Alignment30Consistency() {
        let reps = (0..<5).map { _ in
            makeRep(
                minNoseY: 0.42, maxNoseY: 0.30, duration: 2.0,
                leftShoulderYs: [0.45, 0.45],
                rightShoulderYs: [0.45, 0.45]
            )
        }
        let scores = engine.computeScores(from: reps)!
        let expected = Int(Double(scores.depth) * 0.4 + Double(scores.alignment) * 0.3 + Double(scores.consistency) * 0.3)
        XCTAssertEqual(scores.composite, expected, "Composite should be 40/30/30 weighted")
    }

    // MARK: - Improvement Suggestions

    func testImprovementsEmptyForPerfectForm() {
        let reps = (0..<5).map { _ in
            makeRep(
                minNoseY: 0.42, maxNoseY: 0.30, duration: 2.0,
                leftShoulderYs: [0.45, 0.45, 0.45],
                rightShoulderYs: [0.45, 0.45, 0.45]
            )
        }
        let scores = engine.computeScores(from: reps)!
        XCTAssertTrue(
            scores.improvements.contains { $0.contains("Great form") },
            "Perfect form should get positive feedback"
        )
    }

    func testImprovementsIncludeShoulderHintForAsymmetry() {
        let reps = (0..<5).map { _ in
            makeRep(
                minNoseY: 0.42, maxNoseY: 0.30, duration: 2.0,
                leftShoulderYs: [0.40, 0.40, 0.40],
                rightShoulderYs: [0.55, 0.55, 0.55]
            )
        }
        let scores = engine.computeScores(from: reps)!
        XCTAssertTrue(
            scores.improvements.contains { $0.lowercased().contains("shoulder") },
            "Asymmetric shoulders should produce a shoulder-related improvement"
        )
    }

    func testImprovementsSortedByWorstScoreFirst() {
        let reps = [
            makeRep(minNoseY: 0.42, maxNoseY: 0.30, duration: 1.0,
                    leftShoulderYs: [0.40], rightShoulderYs: [0.55]),
            makeRep(minNoseY: 0.42, maxNoseY: 0.30, duration: 4.0,
                    leftShoulderYs: [0.40], rightShoulderYs: [0.55]),
            makeRep(minNoseY: 0.35, maxNoseY: 0.30, duration: 0.5,
                    leftShoulderYs: [0.40], rightShoulderYs: [0.55]),
        ]
        let scores = engine.computeScores(from: reps)!
        XCTAssertGreaterThanOrEqual(scores.improvements.count, 2, "Multiple sub-80 scores → multiple suggestions")
    }

    // MARK: - Helpers

    private func makeRep(
        minNoseY: CGFloat,
        maxNoseY: CGFloat,
        duration: TimeInterval,
        leftShoulderYs: [CGFloat] = [0.45, 0.45],
        rightShoulderYs: [CGFloat] = [0.45, 0.45]
    ) -> RepCountingEngine.RepMeasurement {
        RepCountingEngine.RepMeasurement(
            minNoseY: minNoseY,
            maxNoseY: maxNoseY,
            minWorldY: nil,
            maxWorldY: nil,
            durationSeconds: duration,
            leftShoulderYs: leftShoulderYs,
            rightShoulderYs: rightShoulderYs,
            leftShoulderWorldYs: [],
            rightShoulderWorldYs: []
        )
    }
}
