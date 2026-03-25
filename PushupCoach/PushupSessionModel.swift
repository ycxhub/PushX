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
    var debugLog: String
    var sessionDiagnosticsJSON: String
    var exportSchemaVersion: Int

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
        reps: [PushupRepRecord] = [],
        debugLog: String = "",
        sessionDiagnosticsJSON: String = "",
        exportSchemaVersion: Int = 2
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
        self.debugLog = debugLog
        self.sessionDiagnosticsJSON = sessionDiagnosticsJSON
        self.exportSchemaVersion = exportSchemaVersion
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

    var providerDisplayName: String {
        if providerType == PoseProviderType.mediaPipe.rawValue || providerType == PoseProviderType.appleVision.rawValue {
            return "PushXPose"
        }
        return providerType
    }
}
