import Foundation

enum SessionExporter {

    // MARK: - Single session

    static func toJSON(session: PushupSession) -> String {
        let dict = sessionDict(session)
        return encodeToJSONString(dict)
    }

    // MARK: - Multi-session

    static func toJSON(sessions: [PushupSession]) -> String {
        guard !sessions.isEmpty else { return "{\"sessions\": []}" }

        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        let sessionDicts = sorted.map { sessionDict($0) }

        let composites = sorted.compactMap(\.compositeScore)
        let depths = sorted.compactMap(\.depthScore)
        let alignments = sorted.compactMap(\.alignmentScore)
        let consistencies = sorted.compactMap(\.consistencyScore)
        let totalReps = sorted.reduce(0) { $0 + $1.repCount }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var summary: [String: Any] = [
            "total_sessions": sorted.count,
            "total_reps": totalReps,
        ]
        if !composites.isEmpty {
            summary["avg_composite"] = composites.reduce(0, +) / composites.count
            summary["composite_trend"] = composites
        }
        if !depths.isEmpty { summary["avg_depth"] = depths.reduce(0, +) / depths.count }
        if !alignments.isEmpty { summary["avg_alignment"] = alignments.reduce(0, +) / alignments.count }
        if !consistencies.isEmpty { summary["avg_consistency"] = consistencies.reduce(0, +) / consistencies.count }

        let root: [String: Any] = [
            "export_date": formatter.string(from: Date()),
            "session_count": sorted.count,
            "date_range": [
                "from": formatter.string(from: sorted.first!.startedAt),
                "to": formatter.string(from: sorted.last!.startedAt),
            ],
            "sessions": sessionDicts,
            "summary": summary,
        ]

        return encodeToJSONString(root)
    }

    // MARK: - Internals

    private static func sessionDict(_ session: PushupSession) -> [String: Any] {
        let formatter = ISO8601DateFormatter()

        var scores: [String: Any] = [:]
        if let c = session.compositeScore { scores["composite"] = c }
        if let d = session.depthScore { scores["depth"] = d }
        if let a = session.alignmentScore { scores["alignment"] = a }
        if let co = session.consistencyScore { scores["consistency"] = co }

        let reps = session.reps
            .sorted { $0.repNumber < $1.repNumber }
            .map { repDict($0) }

        var sessionObj: [String: Any] = [
            "id": session.id.uuidString,
            "date": formatter.string(from: session.startedAt),
            "duration_seconds": round(session.durationSeconds * 10) / 10,
            "rep_count": session.repCount,
            "provider": session.providerType,
        ]
        if !scores.isEmpty { sessionObj["scores"] = scores }
        if !session.improvements.isEmpty { sessionObj["improvements"] = session.improvements }

        return [
            "session": sessionObj,
            "reps": reps,
        ]
    }

    private static func repDict(_ rep: PushupRepRecord) -> [String: Any] {
        var dict: [String: Any] = [
            "number": rep.repNumber,
            "duration_s": round(rep.durationSeconds * 100) / 100,
            "depth_normalized": round(rep.depthScreenSpace * 1000) / 1000,
            "shoulder_asymmetry": round(rep.shoulderAsymmetry * 1000) / 1000,
        ]
        if let dw = rep.depthWorldMeters {
            dict["depth_meters"] = round(dw * 1000) / 1000
        }
        if let aw = rep.shoulderAsymmetryWorld {
            dict["shoulder_asymmetry_world"] = round(aw * 1000) / 1000
        }
        return dict
    }

    private static func encodeToJSONString(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to encode session data\"}"
        }
        return str
    }
}
