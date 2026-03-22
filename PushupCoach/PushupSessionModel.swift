import Foundation
import SwiftData

@Model
final class PushupSession {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var repCount: Int

    var compositeScore: Int?
    var depthScore: Int?
    var alignmentScore: Int?
    var consistencyScore: Int?

    var improvements: [String]
    var providerType: String

    @Relationship(deleteRule: .cascade, inverse: \PushupRepRecord.session)
    var reps: [PushupRepRecord]

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        repCount: Int,
        compositeScore: Int? = nil,
        depthScore: Int? = nil,
        alignmentScore: Int? = nil,
        consistencyScore: Int? = nil,
        improvements: [String] = [],
        providerType: String,
        reps: [PushupRepRecord] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.repCount = repCount
        self.compositeScore = compositeScore
        self.depthScore = depthScore
        self.alignmentScore = alignmentScore
        self.consistencyScore = consistencyScore
        self.improvements = improvements
        self.providerType = providerType
        self.reps = reps
    }

    var durationSeconds: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    var averageRepDuration: Double? {
        guard !reps.isEmpty else { return nil }
        return reps.map(\.durationSeconds).reduce(0, +) / Double(reps.count)
    }

    var hasScores: Bool {
        compositeScore != nil
    }
}
