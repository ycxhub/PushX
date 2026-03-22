import XCTest
import CoreGraphics
@testable import EngineCore

final class LandmarkSmootherTests: XCTestCase {

    // MARK: - Pass-through on First Frame

    func testFirstFramePassesThroughUnchanged() {
        let smoother = LandmarkSmoother(alpha: 0.28)
        let landmarks = [
            Landmark(type: .nose, position: CGPoint(x: 0.5, y: 0.3), confidence: 0.9),
        ]
        let result = smoother.smooth(landmarks: landmarks)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].position.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(result[0].position.y, 0.3, accuracy: 0.001)
    }

    // MARK: - EMA Smoothing

    func testSecondFrameIsSmoothed() {
        let smoother = LandmarkSmoother(alpha: 0.5)
        let first = [Landmark(type: .nose, position: CGPoint(x: 0.5, y: 0.3), confidence: 0.9)]
        _ = smoother.smooth(landmarks: first)

        let second = [Landmark(type: .nose, position: CGPoint(x: 0.7, y: 0.5), confidence: 0.9)]
        let result = smoother.smooth(landmarks: second)

        // EMA: new = alpha * raw + (1-alpha) * prev
        // x: 0.5 * 0.7 + 0.5 * 0.5 = 0.60
        // y: 0.5 * 0.5 + 0.5 * 0.3 = 0.40
        XCTAssertEqual(result[0].position.x, 0.60, accuracy: 0.001)
        XCTAssertEqual(result[0].position.y, 0.40, accuracy: 0.001)
    }

    func testHighAlphaIsMoreResponsive() {
        let responsive = LandmarkSmoother(alpha: 0.9)
        let sluggish = LandmarkSmoother(alpha: 0.1)

        let first = [Landmark(type: .nose, position: CGPoint(x: 0.0, y: 0.0), confidence: 0.9)]
        _ = responsive.smooth(landmarks: first)
        _ = sluggish.smooth(landmarks: first)

        let jump = [Landmark(type: .nose, position: CGPoint(x: 1.0, y: 1.0), confidence: 0.9)]
        let rResult = responsive.smooth(landmarks: jump)
        let sResult = sluggish.smooth(landmarks: jump)

        XCTAssertGreaterThan(rResult[0].position.x, sResult[0].position.x,
                             "High alpha should track the jump more closely")
    }

    // MARK: - Low Confidence Bypass

    func testLowConfidencePassesThroughRawAndClearsHistory() {
        let smoother = LandmarkSmoother(alpha: 0.5)
        let first = [Landmark(type: .nose, position: CGPoint(x: 0.5, y: 0.3), confidence: 0.9)]
        _ = smoother.smooth(landmarks: first)

        let low = [Landmark(type: .nose, position: CGPoint(x: 0.9, y: 0.9), confidence: 0.1)]
        let result = smoother.smooth(landmarks: low)

        XCTAssertEqual(result[0].position.x, 0.9, accuracy: 0.001, "Low confidence should pass through raw")

        // After low-confidence clear, next high-confidence frame should also pass through (no history)
        let next = [Landmark(type: .nose, position: CGPoint(x: 0.2, y: 0.2), confidence: 0.9)]
        let nextResult = smoother.smooth(landmarks: next)
        XCTAssertEqual(nextResult[0].position.x, 0.2, accuracy: 0.001,
                       "After cleared history, first frame passes through")
    }

    // MARK: - Reset

    func testResetClearsSmoothedHistory() {
        let smoother = LandmarkSmoother(alpha: 0.5)
        _ = smoother.smooth(landmarks: [
            Landmark(type: .nose, position: CGPoint(x: 0.5, y: 0.3), confidence: 0.9),
        ])

        smoother.reset()

        let fresh = [Landmark(type: .nose, position: CGPoint(x: 0.8, y: 0.8), confidence: 0.9)]
        let result = smoother.smooth(landmarks: fresh)
        XCTAssertEqual(result[0].position.x, 0.8, accuracy: 0.001, "After reset, should pass through")
        XCTAssertEqual(result[0].position.y, 0.8, accuracy: 0.001)
    }

    // MARK: - Multiple Landmarks

    func testSmoothesEachLandmarkIndependently() {
        let smoother = LandmarkSmoother(alpha: 0.5)
        let frame1 = [
            Landmark(type: .nose, position: CGPoint(x: 0.0, y: 0.0), confidence: 0.9),
            Landmark(type: .leftShoulder, position: CGPoint(x: 1.0, y: 1.0), confidence: 0.9),
        ]
        _ = smoother.smooth(landmarks: frame1)

        let frame2 = [
            Landmark(type: .nose, position: CGPoint(x: 1.0, y: 1.0), confidence: 0.9),
            Landmark(type: .leftShoulder, position: CGPoint(x: 0.0, y: 0.0), confidence: 0.9),
        ]
        let result = smoother.smooth(landmarks: frame2)

        // Both should converge toward 0.5 with alpha=0.5
        XCTAssertEqual(result[0].position.x, 0.5, accuracy: 0.001) // nose: 0.5*1.0 + 0.5*0.0
        XCTAssertEqual(result[1].position.x, 0.5, accuracy: 0.001) // shoulder: 0.5*0.0 + 0.5*1.0
    }
}
