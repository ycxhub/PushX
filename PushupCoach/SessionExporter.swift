import Foundation

enum SessionExporter {
    static let schemaVersion = 2

    static func toJSON(session: PushupSession) -> String {
        let root: [String: Any] = [
            "schema_version": schemaVersion,
            "measurement_support": measurementSupportCatalog(),
            "session": sessionDict(session),
            "diagnostics": diagnosticsDict(for: session) as Any,
        ]
        return encodeToJSONString(root)
    }

    static func toJSON(sessions: [PushupSession]) -> String {
        guard !sessions.isEmpty else {
            return encodeToJSONString([
                "schema_version": schemaVersion,
                "sessions": [],
                "measurement_support": measurementSupportCatalog(),
            ])
        }

        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        let sessionDicts = sorted.map(sessionDict)
        let root: [String: Any] = [
            "schema_version": schemaVersion,
            "export_date": ISO8601DateFormatter().string(from: Date()),
            "session_count": sorted.count,
            "date_range": [
                "from": ISO8601DateFormatter().string(from: sorted.first!.startedAt),
                "to": ISO8601DateFormatter().string(from: sorted.last!.startedAt),
            ],
            "measurement_support": measurementSupportCatalog(),
            "sessions": sessionDicts,
            "summary": multiSessionSummary(sorted),
        ]
        return encodeToJSONString(root)
    }

    private static func sessionDict(_ session: PushupSession) -> [String: Any] {
        let formatter = ISO8601DateFormatter()

        var scores: [String: Any] = [:]
        if let c = session.compositeScore { scores["composite"] = c }
        if let d = session.depthScore { scores["depth"] = d }
        if let a = session.alignmentScore { scores["alignment"] = a }
        if let co = session.consistencyScore { scores["consistency"] = co }

        let sortedReps = session.reps.sorted { $0.repNumber < $1.repNumber }
        let reps = sortedReps.map(repDict)

        var sessionObj: [String: Any] = [
            "id": session.id.uuidString,
            "date": formatter.string(from: session.startedAt),
            "duration_seconds": round(session.durationSeconds * 10) / 10,
            "rep_count": session.repCount,
            "provider": session.providerType,
            "export_schema_version": session.exportSchemaVersion,
            "session_summary": sessionSummary(from: session, reps: sortedReps),
        ]
        if !scores.isEmpty { sessionObj["scores"] = scores }
        if !session.improvements.isEmpty { sessionObj["improvements"] = session.improvements }

        return [
            "session": sessionObj,
            "reps": reps,
            "diagnostics": diagnosticsDict(for: session) as Any,
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

        set(&dict, key: "rep_start_position_y", value: rep.startPositionY, digits: 4)
        set(&dict, key: "rep_bottom_position_y", value: rep.bottomPositionY, digits: 4)
        set(&dict, key: "eccentric_time_s", value: rep.eccentricDurationSeconds, digits: 3)
        set(&dict, key: "bottom_pause_time_s", value: rep.bottomPauseDurationSeconds, digits: 3)
        set(&dict, key: "concentric_time_s", value: rep.concentricDurationSeconds, digits: 3)
        set(&dict, key: "top_pause_time_s", value: rep.topPauseDurationSeconds, digits: 3)
        set(&dict, key: "top_lockout_completeness", value: rep.topLockoutCompleteness, digits: 3)
        set(&dict, key: "hip_asymmetry", value: rep.hipAsymmetry, digits: 4)
        set(&dict, key: "elbow_flare_angle_deg", value: rep.elbowFlareAngle, digits: 2)
        set(&dict, key: "elbow_symmetry_delta_deg", value: rep.elbowSymmetry, digits: 2)
        set(&dict, key: "forearm_verticality_deg", value: rep.forearmVerticality, digits: 2)
        set(&dict, key: "torso_angle_to_floor_deg", value: rep.torsoAngleToFloor, digits: 2)
        set(&dict, key: "body_line_straightness_deg", value: rep.bodyLineStraightness, digits: 2)
        set(&dict, key: "head_neck_alignment_deg", value: rep.headAlignment, digits: 2)
        set(&dict, key: "lateral_weight_shift_proxy", value: rep.lateralDrift, digits: 4)
        set(&dict, key: "center_of_mass_side_to_side_proxy", value: rep.centerOfMassDriftProxy, digits: 4)
        set(&dict, key: "path_jerkiness_proxy", value: rep.pathJerkiness, digits: 4)
        set(&dict, key: "sticking_point_percent", value: rep.stickingPointPercent, digits: 3)
        if let wobbleEvents = rep.wobbleEvents {
            dict["wobble_count"] = wobbleEvents
        }

        return dict
    }

    private static func sessionSummary(from session: PushupSession, reps: [PushupRepRecord]) -> [String: Any] {
        var summary: [String: Any] = [
            "rep_count": session.repCount,
            "duration_seconds": round(session.durationSeconds * 10) / 10,
        ]

        guard !reps.isEmpty else { return summary }

        let depths = reps.map(\.depthScreenSpace)
        let durations = reps.map(\.durationSeconds)
        let shoulderAsymmetry = reps.map(\.shoulderAsymmetry)
        let hipAsymmetry = reps.compactMap(\.hipAsymmetry)
        let torsoAngles = reps.compactMap(\.torsoAngleToFloor)
        let lockout = reps.compactMap(\.topLockoutCompleteness)

        summary["depth_consistency_cv"] = round(coefficientOfVariation(depths) * 1000) / 1000
        summary["tempo_drift_cv"] = round(coefficientOfVariation(durations) * 1000) / 1000
        summary["range_of_motion_dropoff"] = trendDropoff(depths)
        summary["speed_dropoff"] = trendDropoff(reps.compactMap(\.concentricDurationSeconds))
        summary["asymmetry_increase"] = trendIncrease(shoulderAsymmetry)
        summary["hip_asymmetry_increase"] = trendIncrease(hipAsymmetry)
        summary["rep_where_form_first_degrades"] = firstDegradedRep(reps)
        summary["average_shoulder_asymmetry"] = roundedAverage(shoulderAsymmetry, digits: 4)
        summary["average_hip_asymmetry"] = roundedAverage(hipAsymmetry, digits: 4) as Any
        summary["average_torso_angle_to_floor_deg"] = roundedAverage(torsoAngles, digits: 2) as Any
        summary["average_top_lockout_completeness"] = roundedAverage(lockout, digits: 3) as Any
        summary["wobble_events_total"] = reps.compactMap(\.wobbleEvents).reduce(0, +)
        return summary
    }

    private static func multiSessionSummary(_ sessions: [PushupSession]) -> [String: Any] {
        let composites = sessions.compactMap(\.compositeScore)
        let totalReps = sessions.reduce(0) { $0 + $1.repCount }
        return [
            "total_sessions": sessions.count,
            "total_reps": totalReps,
            "avg_composite": composites.isEmpty ? NSNull() : composites.reduce(0, +) / composites.count,
        ]
    }

    private static func diagnosticsDict(for session: PushupSession) -> Any? {
        guard !session.sessionDiagnosticsJSON.isEmpty,
              let data = session.sessionDiagnosticsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return object
    }

    private static func measurementSupportCatalog() -> [String: Any] {
        [
            "implemented_direct": [
                "depth_per_rep",
                "depth_consistency",
                "rep_duration",
                "eccentric_time",
                "bottom_pause_time",
                "concentric_time",
                "top_pause_time",
                "shoulder_asymmetry",
                "top_lockout_completeness",
            ],
            "implemented_proxy": [
                "hip_asymmetry",
                "elbow_flare_angle",
                "left_right_elbow_symmetry",
                "forearm_verticality",
                "torso_angle_to_floor",
                "head_neck_alignment",
                "body_line_straightness",
                "lateral_weight_shift",
                "center_of_mass_side_to_side_drift",
                "path_smoothness",
                "sticking_point_location",
                "wobble_count",
                "rep_where_form_first_degrades",
                "range_of_motion_dropoff",
                "asymmetry_increase_over_set",
                "speed_dropoff_over_set",
                "lockout_to_lockout_consistency",
            ],
            "not_reliable_single_angle": [
                "true_center_of_mass",
                "precise_weight_distribution",
                "absolute_load_shift",
            ],
        ]
    }

    private static func coefficientOfVariation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return 0 }
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return sqrt(variance) / mean
    }

    private static func roundedAverage(_ values: [Double], digits: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let scale = pow(10, digits)
        return (values.reduce(0, +) / Double(values.count) * scale).rounded() / scale
    }

    private static func trendDropoff(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        let segment = max(1, values.count / 3)
        let first = Array(values.prefix(segment))
        let last = Array(values.suffix(segment))
        guard let firstAvg = roundedAverage(first, digits: 4), firstAvg != 0,
              let lastAvg = roundedAverage(last, digits: 4) else { return nil }
        return round(((firstAvg - lastAvg) / firstAvg) * 1000) / 1000
    }

    private static func trendIncrease(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        let segment = max(1, values.count / 3)
        let first = Array(values.prefix(segment))
        let last = Array(values.suffix(segment))
        guard let firstAvg = roundedAverage(first, digits: 4),
              let lastAvg = roundedAverage(last, digits: 4) else { return nil }
        return round((lastAvg - firstAvg) * 1000) / 1000
    }

    private static func firstDegradedRep(_ reps: [PushupRepRecord]) -> Int? {
        for rep in reps {
            if let lockout = rep.topLockoutCompleteness, lockout < 0.85 {
                return rep.repNumber
            }
            if rep.depthScreenSpace < (reps.first?.depthScreenSpace ?? rep.depthScreenSpace) * 0.82 {
                return rep.repNumber
            }
            if rep.shoulderAsymmetry > (reps.first?.shoulderAsymmetry ?? rep.shoulderAsymmetry) * 1.3 {
                return rep.repNumber
            }
        }
        return nil
    }

    private static func set(_ dict: inout [String: Any], key: String, value: Double?, digits: Double) {
        guard let value else { return }
        let scale = pow(10, digits)
        dict[key] = (value * scale).rounded() / scale
    }

    private static func encodeToJSONString(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to encode session data\"}"
        }
        return str
    }
}
