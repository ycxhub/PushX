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

    var relativeDayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(startedAt) {
            return "Today"
        }
        if calendar.isDateInYesterday(startedAt) {
            return "Yesterday"
        }
        return startedAt.formatted(.dateTime.month(.abbreviated).day())
    }

    var timeLabel: String {
        startedAt.formatted(.dateTime.hour().minute())
    }

    var averageLockout: Double? {
        let values = reps.compactMap(\.topLockoutCompleteness)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageHipStabilityDrift: Double? {
        let values = reps.compactMap(\.hipAsymmetry)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWobbleEvents: Double? {
        let values = reps.compactMap { $0.wobbleEvents.map(Double.init) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var sessionHighlights: [String] {
        var highlights: [String] = []

        if let averageRepDuration {
            highlights.append("Tempo averaged \(String(format: "%.1fs", averageRepDuration)) per rep.")
        }

        if let averageLockout {
            if averageLockout >= 0.9 {
                highlights.append("Strong top lockout across the set.")
            } else if averageLockout < 0.72 {
                highlights.append("Lockout faded late in the set.")
            }
        }

        if let averageHipStabilityDrift {
            if averageHipStabilityDrift < 0.03 {
                highlights.append("Hips stayed steady through most reps.")
            } else {
                highlights.append("Hip stability drifted under fatigue.")
            }
        }

        if let averageWobbleEvents, averageWobbleEvents > 1.0 {
            highlights.append("A few reps showed visible wobble under load.")
        }

        if repCount >= 12 {
            highlights.append("High-volume set completed.")
        }

        return Array(highlights.prefix(3))
    }

    var quickCoachInsights: [String] {
        var insights: [String] = []

        if let compositeScore {
            if compositeScore >= 85 {
                insights.append("Best cue: keep this same rhythm and depth next set.")
            } else if compositeScore >= 70 {
                insights.append("Best cue: keep depth consistent as the set gets harder.")
            } else {
                insights.append("Best cue: slow down slightly and focus on cleaner top and bottom positions.")
            }
        }

        if let averageLockout, averageLockout < 0.75 {
            insights.append("Finish each rep taller at the top before starting the next one.")
        }

        if let averageHipStabilityDrift, averageHipStabilityDrift >= 0.03 {
            insights.append("Brace harder through the midline to reduce hip movement.")
        }

        if let averageRepDuration, averageRepDuration < 0.6 {
            insights.append("Try a calmer tempo. A touch more control should improve scoring.")
        }

        if insights.isEmpty {
            insights.append("Solid set. Stay consistent and repeat the same setup next session.")
        }

        return Array(insights.prefix(3))
    }
}
