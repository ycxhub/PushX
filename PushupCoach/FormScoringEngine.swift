import Foundation
import CoreGraphics

struct FormScores {
    let depth: Int
    let alignment: Int
    let consistency: Int
    let composite: Int
    let improvements: [String]
}

final class FormScoringEngine {
    func computeScores(from reps: [RepCountingEngine.RepMeasurement]) -> FormScores? {
        guard reps.count >= 2 else { return nil }

        let depthScore = computeDepthScore(reps)
        let alignmentScore = computeAlignmentScore(reps)
        let consistencyScore = computeConsistencyScore(reps)

        let composite = Int(Double(depthScore) * 0.4 + Double(alignmentScore) * 0.3 + Double(consistencyScore) * 0.3)
        let improvements = generateImprovements(depth: depthScore, alignment: alignmentScore, consistency: consistencyScore, reps: reps)

        return FormScores(
            depth: depthScore,
            alignment: alignmentScore,
            consistency: consistencyScore,
            composite: composite,
            improvements: improvements
        )
    }

    // MARK: - Depth

    private func computeDepthScore(_ reps: [RepCountingEngine.RepMeasurement]) -> Int {
        let depths = reps.map { $0.minNoseY - $0.maxNoseY }
        guard let maxDepth = depths.max(), maxDepth > 0 else { return 50 }

        var score: Double = 0
        for depth in depths {
            let ratio = depth / maxDepth
            score += min(ratio / 0.7, 1.0)
        }
        score = (score / Double(depths.count)) * 100
        return clampScore(score)
    }

    // MARK: - Alignment

    private func computeAlignmentScore(_ reps: [RepCountingEngine.RepMeasurement]) -> Int {
        var totalAsymmetry: Double = 0
        var sampleCount = 0

        for rep in reps {
            let pairCount = min(rep.leftShoulderYs.count, rep.rightShoulderYs.count)
            for i in 0..<pairCount {
                let diff = abs(rep.leftShoulderYs[i] - rep.rightShoulderYs[i])
                totalAsymmetry += Double(diff)
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return 75 }

        let avgAsymmetry = totalAsymmetry / Double(sampleCount)
        let maxAcceptable = 0.05
        let score = max(0, 1.0 - (avgAsymmetry / maxAcceptable)) * 100
        return clampScore(score)
    }

    // MARK: - Consistency

    private func computeConsistencyScore(_ reps: [RepCountingEngine.RepMeasurement]) -> Int {
        let durations = reps.map { $0.durationSeconds }
        let depths = reps.map { $0.minNoseY - $0.maxNoseY }

        let durationCV = coefficientOfVariation(durations)
        let depthCV = coefficientOfVariation(depths.map { Double($0) })

        let durationScore = max(0, 1.0 - durationCV) * 100
        let depthScore = max(0, 1.0 - depthCV) * 100
        let combined = (durationScore + depthScore) / 2.0
        return clampScore(combined)
    }

    // MARK: - Improvements

    private func generateImprovements(depth: Int, alignment: Int, consistency: Int, reps: [RepCountingEngine.RepMeasurement]) -> [String] {
        var suggestions: [(score: Int, text: String)] = []

        if depth < 80 {
            let depthValues = reps.map { $0.minNoseY - $0.maxNoseY }
            let lastThird = Array(depthValues.suffix(reps.count / 3 + 1))
            let firstThird = Array(depthValues.prefix(reps.count / 3 + 1))
            let lastAvg = lastThird.reduce(CGFloat(0), +) / CGFloat(lastThird.count)
            let firstAvg = firstThird.reduce(CGFloat(0), +) / CGFloat(firstThird.count)

            if lastAvg < firstAvg * 0.8 {
                suggestions.append((depth, "Your depth dropped in the last few reps — try to maintain the same range even when tired."))
            } else {
                suggestions.append((depth, "Try going deeper on each rep. Focus on lowering your chest closer to the ground."))
            }
        }

        if alignment < 80 {
            suggestions.append((alignment, "Keep your shoulders level. One side may be dipping more than the other."))
        }

        if consistency < 80 {
            let durations = reps.map { $0.durationSeconds }
            if let maxD = durations.max(), let minD = durations.min(), maxD > minD * 2.0 {
                suggestions.append((consistency, "Your rep speed varies a lot. Try to keep a steady tempo throughout."))
            } else {
                suggestions.append((consistency, "Work on making each rep feel the same — same depth, same speed."))
            }
        }

        if suggestions.isEmpty {
            suggestions.append((100, "Great form! Keep it up."))
        }

        return suggestions.sorted { $0.score < $1.score }.map { $0.text }
    }

    // MARK: - Math helpers

    private func coefficientOfVariation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return 0 }
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return sqrt(variance) / mean
    }

    private func clampScore(_ value: Double) -> Int {
        Int(min(100, max(0, value)))
    }
}
