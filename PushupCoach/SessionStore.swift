import Foundation
import SwiftData
import os

/// CRUD operations for PushupSession persistence.
enum SessionStore {

    private static let logger = Logger(subsystem: "com.pushx", category: "SessionStore")

    static func save(session: PushupSession, context: ModelContext) {
        context.insert(session)
        do {
            try context.save()
        } catch {
            logger.error("Failed to save session: \(error.localizedDescription)")
        }
    }

    static func fetchAll(context: ModelContext) -> [PushupSession] {
        let descriptor = FetchDescriptor<PushupSession>(
            sortBy: [SortDescriptor(\PushupSession.startedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch sessions: \(error.localizedDescription)")
            return []
        }
    }

    static func fetchRecent(limit: Int, context: ModelContext) -> [PushupSession] {
        var descriptor = FetchDescriptor<PushupSession>(
            sortBy: [SortDescriptor(\PushupSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch recent sessions: \(error.localizedDescription)")
            return []
        }
    }

    static func delete(session: PushupSession, context: ModelContext) {
        context.delete(session)
        do {
            try context.save()
        } catch {
            logger.error("Failed to delete session: \(error.localizedDescription)")
        }
    }

    /// Assemble a PushupSession from engine outputs.
    static func assemble(
        repMeasurements: [RepCountingEngine.RepMeasurement],
        formScores: FormScores?,
        providerType: PoseProviderType,
        startedAt: Date,
        endedAt: Date,
        debugLog: String = ""
    ) -> PushupSession {
        let repRecords = repMeasurements.enumerated().map { index, measurement in
            PushupRepRecord(from: measurement, repNumber: index + 1)
        }

        let session = PushupSession(
            startedAt: startedAt,
            endedAt: endedAt,
            repCount: repMeasurements.count,
            compositeScore: formScores?.composite,
            depthScore: formScores?.depth,
            alignmentScore: formScores?.alignment,
            consistencyScore: formScores?.consistency,
            improvements: formScores?.improvements ?? [],
            providerType: providerType.rawValue,
            reps: repRecords,
            debugLog: debugLog
        )

        return session
    }
}
