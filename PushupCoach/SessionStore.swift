import Foundation
import SwiftData
import os
import UIKit

struct SessionDiagnostics: Codable {
    let schemaVersion: Int
    let appVersion: String
    let buildNumber: String
    let deviceModel: String
    let osVersion: String
    let provider: String
    let startedAt: Date
    let endedAt: Date
    let processedFrameCount: Int
    let repCount: Int
    let camera: CameraDiagnostics
    let visibility: VisibilityDiagnostics
    let tracking: TrackingDiagnostics
    let counting: CountingDiagnostics
}

struct CameraDiagnostics: Codable {
    let startupStatus: String
    let retryCount: Int
    let interruptionCount: Int
    let runtimeErrorCount: Int
    let startupEvents: [String]
    let failureMessages: [String]
}

struct VisibilityDiagnostics: Codable {
    let framesWithBody: Int
    let framesWithHead: Int
    let framesOutOfFrame: Int
    let framesTooClose: Int
    let framesTooFar: Int
    let framesUsableButMarginal: Int
    let averageShoulderSpan: Double?
    let averageHeadVisibility: Double?
}

struct TrackingDiagnostics: Codable {
    let lostFrames: Int
    let liningUpFrames: Int
    let lockedFrames: Int
    let phaseFrames: [String: Int]
}

struct CountingDiagnostics: Codable {
    let readyLocks: Int
    let bootstrapStarts: Int
    let motionWhileIdleEvents: Int
    let pauseEvents: Int
    let firstRepBootstrapped: Bool
    let rejectionCounts: [String: Int]
}

@MainActor
final class SessionDiagnosticsCollector {
    private(set) var startedAt: Date?
    private var provider: String = ""
    private var retryCount = 0
    private var interruptionCount = 0
    private var runtimeErrorCount = 0
    private var startupEvents: [String] = []
    private var failureMessages: [String] = []
    private var latestStartupStatus = "not_started"

    private var framesWithBody = 0
    private var framesWithHead = 0
    private var framesOutOfFrame = 0
    private var framesTooClose = 0
    private var framesTooFar = 0
    private var framesUsableButMarginal = 0
    private var shoulderSpanSamples: [Double] = []
    private var headVisibilitySamples: [Double] = []

    private var lostFrames = 0
    private var liningUpFrames = 0
    private var lockedFrames = 0
    private var phaseFrames: [String: Int] = [:]

    func beginSession(providerType: PoseProviderType, startedAt: Date) {
        self.provider = providerType.rawValue
        self.startedAt = startedAt
        startupEvents = []
        failureMessages = []
        latestStartupStatus = "starting"
        retryCount = 0
        interruptionCount = 0
        runtimeErrorCount = 0
        framesWithBody = 0
        framesWithHead = 0
        framesOutOfFrame = 0
        framesTooClose = 0
        framesTooFar = 0
        framesUsableButMarginal = 0
        shoulderSpanSamples = []
        headVisibilitySamples = []
        lostFrames = 0
        liningUpFrames = 0
        lockedFrames = 0
        phaseFrames = [:]
    }

    func noteRetry() {
        retryCount += 1
        startupEvents.append("retry_requested")
    }

    func noteCameraEvent(_ message: String) {
        startupEvents.append(message)
        if message.localizedCaseInsensitiveContains("runtime error") {
            runtimeErrorCount += 1
        }
        if message.localizedCaseInsensitiveContains("interrupted") {
            interruptionCount += 1
        }
        if message.localizedCaseInsensitiveContains("startRunning() returned") {
            latestStartupStatus = "running"
        }
    }

    func noteCameraFailure(_ message: String) {
        latestStartupStatus = "failed"
        failureMessages.append(message)
    }

    func noteCameraSuccess() {
        latestStartupStatus = "running"
    }

    func recordFrame(pose: PoseResult?, trackingState: PoseTrackingState, phase: RepCountingEngine.Phase) {
        phaseFrames[phase.rawValue, default: 0] += 1
        switch trackingState {
        case .lost:
            lostFrames += 1
        case .liningUp:
            liningUpFrames += 1
        case .locked:
            lockedFrames += 1
        }

        guard let pose else { return }
        if pose.isBodyDetected {
            framesWithBody += 1
        }
        if pose.headReferenceY != nil {
            framesWithHead += 1
        }
        if let bbox = pose.boundingBox(minConfidence: 0.15) {
            let inset = PushupPoseConstants.safeFrameInset
            if bbox.minX < inset || bbox.maxX > (1 - inset) || bbox.minY < inset || bbox.maxY > (1 - inset) {
                framesOutOfFrame += 1
            }
        }

        switch pose.distanceAssessment {
        case .tooClose:
            framesTooClose += 1
        case .tooFar:
            framesTooFar += 1
        case .usable:
            framesUsableButMarginal += 1
        case .unavailable, .ideal:
            break
        }

        if let span = pose.shoulderSpanForCalibrationMetric {
            shoulderSpanSamples.append(Double(span))
        }
        headVisibilitySamples.append(pose.headVisibilityScore)
    }

    func finalize(
        endedAt: Date,
        processedFrameCount: Int,
        repCount: Int,
        engineDiagnostics: RepCountingEngine.DiagnosticsSnapshot
    ) -> SessionDiagnostics {
        SessionDiagnostics(
            schemaVersion: 2,
            appVersion: appVersion,
            buildNumber: buildNumber,
            deviceModel: deviceModel,
            osVersion: UIDevice.current.systemVersion,
            provider: provider,
            startedAt: startedAt ?? endedAt,
            endedAt: endedAt,
            processedFrameCount: processedFrameCount,
            repCount: repCount,
            camera: CameraDiagnostics(
                startupStatus: latestStartupStatus,
                retryCount: retryCount,
                interruptionCount: interruptionCount,
                runtimeErrorCount: runtimeErrorCount,
                startupEvents: startupEvents,
                failureMessages: failureMessages
            ),
            visibility: VisibilityDiagnostics(
                framesWithBody: framesWithBody,
                framesWithHead: framesWithHead,
                framesOutOfFrame: framesOutOfFrame,
                framesTooClose: framesTooClose,
                framesTooFar: framesTooFar,
                framesUsableButMarginal: framesUsableButMarginal,
                averageShoulderSpan: average(shoulderSpanSamples),
                averageHeadVisibility: average(headVisibilitySamples)
            ),
            tracking: TrackingDiagnostics(
                lostFrames: lostFrames,
                liningUpFrames: liningUpFrames,
                lockedFrames: lockedFrames,
                phaseFrames: phaseFrames
            ),
            counting: CountingDiagnostics(
                readyLocks: engineDiagnostics.readyLocks,
                bootstrapStarts: engineDiagnostics.bootstrapStarts,
                motionWhileIdleEvents: engineDiagnostics.motionWhileIdleEvents,
                pauseEvents: engineDiagnostics.pauseEvents,
                firstRepBootstrapped: engineDiagnostics.firstRepBootstrapped,
                rejectionCounts: engineDiagnostics.rejectionCounts
            )
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

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
        debugLog: String = "",
        diagnostics: SessionDiagnostics? = nil
    ) -> PushupSession {
        let repRecords = repMeasurements.enumerated().map { index, measurement in
            PushupRepRecord(from: measurement, repNumber: index + 1)
        }

        let diagnosticsJSON: String
        if let diagnostics,
           let data = try? JSONEncoder().encode(diagnostics),
           let string = String(data: data, encoding: .utf8) {
            diagnosticsJSON = string
        } else {
            diagnosticsJSON = ""
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
            debugLog: debugLog,
            sessionDiagnosticsJSON: diagnosticsJSON,
            exportSchemaVersion: 2
        )

        return session
    }
}
