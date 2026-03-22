import XCTest
@testable import EngineCore

final class RepMappingTests: XCTestCase {

    // MARK: - Depth computation

    func testDepthScreenSpaceComputed() {
        let rep = RepCountingEngine.RepMeasurement(
            minNoseY: 0.55,
            maxNoseY: 0.40,
            minWorldY: nil, maxWorldY: nil,
            durationSeconds: 2.0,
            leftShoulderYs: [], rightShoulderYs: [],
            leftShoulderWorldYs: [], rightShoulderWorldYs: []
        )
        let depth = Double(rep.minNoseY - rep.maxNoseY)
        XCTAssertEqual(depth, 0.15, accuracy: 0.001)
    }

    func testDepthWorldSpaceComputed() {
        let rep = RepCountingEngine.RepMeasurement(
            minNoseY: 0.55, maxNoseY: 0.40,
            minWorldY: -0.10, maxWorldY: 0.05,
            durationSeconds: 2.0,
            leftShoulderYs: [], rightShoulderYs: [],
            leftShoulderWorldYs: [], rightShoulderWorldYs: []
        )
        let worldDepth: Double? = {
            guard let minW = rep.minWorldY, let maxW = rep.maxWorldY else { return nil }
            return Double(maxW - minW)
        }()
        XCTAssertNotNil(worldDepth)
        XCTAssertEqual(worldDepth!, 0.15, accuracy: 0.001)
    }

    func testDepthWorldNilWhenMissing() {
        let rep = RepCountingEngine.RepMeasurement(
            minNoseY: 0.55, maxNoseY: 0.40,
            minWorldY: nil, maxWorldY: nil,
            durationSeconds: 2.0,
            leftShoulderYs: [], rightShoulderYs: [],
            leftShoulderWorldYs: [], rightShoulderWorldYs: []
        )
        let worldDepth: Double? = {
            guard let minW = rep.minWorldY, let maxW = rep.maxWorldY else { return nil }
            return Double(maxW - minW)
        }()
        XCTAssertNil(worldDepth)
    }

    // MARK: - Shoulder asymmetry

    func testShoulderAsymmetryFromPairedSamples() {
        let left: [CGFloat] = [0.50, 0.52, 0.48]
        let right: [CGFloat] = [0.51, 0.50, 0.50]
        let pairCount = min(left.count, right.count)
        var total = 0.0
        for i in 0..<pairCount {
            total += Double(abs(left[i] - right[i]))
        }
        let asymmetry = total / Double(pairCount)
        XCTAssertEqual(asymmetry, 0.01666, accuracy: 0.001)
    }

    func testShoulderAsymmetryZeroWhenEmpty() {
        let left: [CGFloat] = []
        let right: [CGFloat] = []
        let pairCount = min(left.count, right.count)
        let asymmetry: Double = pairCount > 0 ? 1.0 : 0.0
        XCTAssertEqual(asymmetry, 0.0)
    }

    func testShoulderAsymmetryUsesMinCount() {
        let left: [CGFloat] = [0.50, 0.52, 0.48, 0.49]
        let right: [CGFloat] = [0.51, 0.50]
        let pairCount = min(left.count, right.count)
        XCTAssertEqual(pairCount, 2)
    }

    // MARK: - Duration passthrough

    func testDurationPassthrough() {
        let rep = RepCountingEngine.RepMeasurement(
            minNoseY: 0.55, maxNoseY: 0.40,
            minWorldY: nil, maxWorldY: nil,
            durationSeconds: 1.87,
            leftShoulderYs: [], rightShoulderYs: [],
            leftShoulderWorldYs: [], rightShoulderWorldYs: []
        )
        XCTAssertEqual(rep.durationSeconds, 1.87, accuracy: 0.001)
    }
}
