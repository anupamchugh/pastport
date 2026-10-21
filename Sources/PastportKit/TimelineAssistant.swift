import Foundation

/// A screenshot the person chose to add. Only scrubbed OCR text is kept.
public struct AddedScreenshot: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let addedAt: Date
    public let evidence: ScreenshotEvidence

    public init(id: UUID = UUID(), name: String, addedAt: Date = Date(), evidence: ScreenshotEvidence) {
        self.id = id
        self.name = name
        self.addedAt = addedAt
        self.evidence = evidence
    }
}

/// The deterministic facts the timeline assistant may see. Built in code, never by the model.
public struct TimelineEvidence: Sendable, Equatable {
    public var window: String
    public var photoEvents: [PhotoEvent]
    public var screenshots: [AddedScreenshot]
    /// False on iPhone and iPad: iOS does not let apps read Safari history.
    public var historyAvailable: Bool
    /// The trail open when the question was asked; it decides which tools the model gets.
    public var trail: TimelineTrail

    public init(window: String, photoEvents: [PhotoEvent], screenshots: [AddedScreenshot], historyAvailable: Bool,
                trail: TimelineTrail = .overview) {
        self.window = window
        self.photoEvents = photoEvents
        self.screenshots = screenshots
        self.historyAvailable = historyAvailable
        self.trail = trail
    }

    public var isEmpty: Bool { photoEvents.isEmpty && screenshots.isEmpty }

    public var countsLine: String {
        let photos = photoEvents.reduce(0) { $0 + $1.photoCount }
        let shots = photoEvents.reduce(0) { $0 + $1.screenshotCount }
        let history = historyAvailable ? "read separately" : "not readable on this device"
        return "counts: window \(window); \(photoEvents.count) photo events; \(photos) photos; "
            + "\(shots) screenshots counted in Photos; \(screenshots.count) screenshots added; Safari history \(history)"
    }

    public var photoLines: [String] {
        guard !photoEvents.isEmpty else { return ["photo activity: none read"] }
        return photoEvents.prefix(8).map { event in
            let start = event.start.formatted(date: .abbreviated, time: .omitted)
            let end = event.end.formatted(date: .abbreviated, time: .omitted)
            let labels = event.labels.isEmpty ? "none" : event.labels.prefix(5).joined(separator: ", ")
            return "photo activity: \(start == end ? start : start + " to " + end): "
                + "\(event.photoCount) photos, \(event.screenshotCount) screenshots; scene labels: \(labels)"
        }
    }

    /// Screenshot text reaches a model only because the person added that screenshot here.
    public var screenshotLines: [String] {
        guard !screenshots.isEmpty else { return ["added screenshots: none"] }
        return screenshots.enumerated().map { index, shot in
            // Adding a screenshot is the person's opt-in, so sensitive kinds are allowed here.
            let text = (shot.evidence.narrationText(allowSensitive: true) ?? "")
                .replacingOccurrences(of: "\n", with: " / ")
            return "added screenshots: #\(index + 1) \(shot.evidence.kind.rawValue), "
                + "\(shot.evidence.redactionCount) redactions: " + String(text.prefix(600))
        }
    }

    /// Hidden items by kind across the added screenshots. Counts only; never the hidden text,
    /// and no screenshot text at all, so the Privacy trail can use it alone.
    public var redactionSummary: String {
        let total = screenshots.map(\.evidence.redactions).reduce(RedactionCounts.zero, +)
        return "redactions: \(total.email) email addresses, \(total.otp) one-time codes, \(total.card) card numbers "
            + "hidden across \(screenshots.count) added screenshots"
    }

    /// Bookings found in added screenshots: kind, date and title line.
    public var bookingLines: [String] {
        let found = screenshots.enumerated().compactMap { index, shot in
            BookingFromScreenshot.detect(shot.evidence).map { (index, $0) }
        }
        guard !found.isEmpty else { return ["bookings: none found in added screenshots"] }
        return found.map { index, booking in
            "bookings: #\(index + 1) \(booking.kind.rawValue) dated "
                + booking.date.formatted(date: .abbreviated, time: .omitted) + ": " + booking.title
        }
    }

    public var lines: [String] { [countsLine] + photoLines + screenshotLines + [redactionSummary] + bookingLines }

    /// The answer when no model runs. Every number comes from the lines above.
    public var deterministicSummary: String {
        if isEmpty {
            return "Nothing has been read yet. Read photo activity or add a screenshot, then ask again."
                + (historyAvailable ? "" : " Safari history is not readable on this device.")
        }
        var parts: [String] = []
        if !photoEvents.isEmpty {
            let photos = photoEvents.reduce(0) { $0 + $1.photoCount }
            let shots = photoEvents.reduce(0) { $0 + $1.screenshotCount }
            parts.append("Photos show \(photoEvents.count) activity burst\(photoEvents.count == 1 ? "" : "s") with \(photos) photo\(photos == 1 ? "" : "s") and \(shots) screenshot\(shots == 1 ? "" : "s") counted.")
        }
        if !screenshots.isEmpty {
            let kinds = screenshots.map(\.evidence.kind.rawValue).joined(separator: ", ")
            parts.append("You added \(screenshots.count) screenshot\(screenshots.count == 1 ? "" : "s") (\(kinds)); their text was scrubbed before use.")
        }
        return parts.joined(separator: " ")
    }
}

/// One update of a streamed answer. Each value replaces the previous one.
public struct TimelineAnswerProgress: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case model
        /// Code wrote this answer; `reason` says why the model did not.
        case facts(reason: String)
    }

    public let text: String
    public let toolsUsed: [String]
    public let source: Source
    /// The source labels the answer drew on, kept only when a matching tool was called.
    public let evidenceKinds: [EvidenceKind]

    public init(text: String, toolsUsed: [String] = [], source: Source, evidenceKinds: [EvidenceKind] = []) {
        self.text = text
        self.toolsUsed = toolsUsed
        self.source = source
        self.evidenceKinds = evidenceKinds
    }
}

/// Which kind of evidence an answer used, shown as its source label.
public enum EvidenceKind: String, CaseIterable, Sendable {
    case photoActivity
    case screenshot

    public var sourceLabel: String {
        switch self {
        case .photoActivity: EvidenceCard.Source.photoActivity.rawValue
        case .screenshot: EvidenceCard.Source.screenshot.rawValue
        }
    }

    /// The tools whose output is this kind of evidence.
    var tools: Set<String> {
        switch self {
        case .photoActivity: [TimelineTools.photoActivity, TimelineTools.counts]
        case .screenshot: [TimelineTools.addedScreenshots, TimelineTools.bookings, TimelineTools.redactionSummary]
        }
    }
}

/// The evidence and trail an iOS 27 dynamic profile reads. A profile may be evaluated off the
/// caller's executor, so it publishes one coherent immutable snapshot, as `JourneyProfileState` does.
public final class TimelineProfileState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimelineEvidence

    public init(evidence: TimelineEvidence) { value = evidence }

    public var snapshot: TimelineEvidence {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    public func update(_ evidence: TimelineEvidence) {
        lock.lock(); defer { lock.unlock() }
        value = evidence
    }
}

/// The seam between the timeline and a language model. Tests use a fake.
public protocol TimelineAnswering: Sendable {
    func answer(_ question: String, evidence: TimelineEvidence) -> AsyncThrowingStream<TimelineAnswerProgress, any Error>
}

/// Which read-only tools the model gets on each trail. Shared by the iOS 26 and iOS 27 paths.
public enum TimelineTools {
    public static let counts = "timeline_counts"
    public static let photoActivity = "photo_activity"
    public static let addedScreenshots = "added_screenshots"
    public static let bookings = "bookings"
    public static let redactionSummary = "redaction_summary"

    /// Privacy gets counts only: no tool that returns screenshot text.
    public static func names(for trail: TimelineTrail) -> [String] {
        switch trail {
        case .overview: [counts, photoActivity, addedScreenshots]
        case .travel: [photoActivity, addedScreenshots, bookings]
        case .photos: [photoActivity, counts]
        case .privacy: [counts, redactionSummary]
        }
    }

    /// Tools whose output includes text read from a screenshot.
    public static let screenshotText: Set<String> = [addedScreenshots, bookings]
}

/// Code-side checks shared by every timeline answer.
public enum TimelineAnswerPolicy {
    /// Text the model wrote may be shown only when every number in it appears in the evidence.
    public static func allows(_ text: String, evidence: TimelineEvidence) -> Bool {
        HistoryJourneyValidation.allowsNarrative(text, evidenceLines: evidence.lines)
    }

    /// A claimed kind stays only when a tool of that kind actually ran.
    public static func keptKinds(_ claimed: [EvidenceKind], toolsCalled: [String]) -> [EvidenceKind] {
        var seen = Set<EvidenceKind>()
        return claimed.filter { !$0.tools.isDisjoint(with: toolsCalled) && seen.insert($0).inserted }
    }

    /// What to send after the stream ends, given the model's finished text and what was shown.
    public static func finalProgress(raw: String, shown: String, toolsUsed: [String],
                                     evidence: TimelineEvidence,
                                     claimedKinds: [EvidenceKind] = []) -> TimelineAnswerProgress? {
        let finished = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Each streamed partial was checked on its own; the finished text decides what stays.
        guard !finished.isEmpty, allows(finished, evidence: evidence) else {
            return TimelineAnswerProgress(text: evidence.deterministicSummary, toolsUsed: toolsUsed,
                                          source: .facts(reason: "The model's answer did not match the recorded facts."))
        }
        let kinds = keptKinds(claimedKinds, toolsCalled: toolsUsed)
        guard finished != shown || !kinds.isEmpty else { return nil }
        return TimelineAnswerProgress(text: finished, toolsUsed: toolsUsed, source: .model, evidenceKinds: kinds)
    }

    static let instructions = """
    You answer questions about the person's own recent timeline on this device.
    Use the tools to read the facts. Use only numbers and dates that a tool returned.
    A screenshot of a booking or receipt does not prove a trip or a payment happened.
    If the facts do not answer the question, say you don't know. Two or three short sentences.
    """
}

#if canImport(FoundationModels)
import FoundationModels

/// Apple's on-device model with three read-only tools over the in-memory evidence.
@available(macOS 26, iOS 26, *)
public struct FoundationTimelineAnswerer: TimelineAnswering {
    public init() {}

    public func answer(_ question: String, evidence: TimelineEvidence) -> AsyncThrowingStream<TimelineAnswerProgress, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let availability = SystemLanguageModel.default.availability
                guard case .available = availability else {
                    continuation.yield(TimelineAnswerProgress(
                        text: evidence.deterministicSummary,
                        source: .facts(reason: Self.reason(for: availability))
                    ))
                    continuation.finish()
                    return
                }
                let log = TimelineToolLog()
                let session = Self.session(for: evidence, log: log)
                var shown = ""
                var raw = ""
                var claimed: [EvidenceKind] = []
                do {
                    for try await snapshot in session.streamResponse(to: question, generating: TimelineAnswerPayload.self) {
                        try Task.checkCancellation()
                        if let kinds = snapshot.content.evidenceKinds { claimed = kinds.map(\.kind) }
                        guard let text = snapshot.content.answer else { continue }
                        raw = text
                        guard text != shown, TimelineAnswerPolicy.allows(text, evidence: evidence) else { continue }
                        shown = text
                        continuation.yield(TimelineAnswerProgress(text: text, toolsUsed: log.names, source: .model))
                    }
                    if let final = TimelineAnswerPolicy.finalProgress(raw: raw, shown: shown, toolsUsed: log.names,
                                                                      evidence: evidence, claimedKinds: claimed) {
                        continuation.yield(final)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.yield(TimelineAnswerProgress(
                        text: evidence.deterministicSummary, toolsUsed: log.names,
                        source: .facts(reason: "Apple Intelligence could not finish this answer.")
                    ))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// iOS 27: a dynamic profile keyed on the trail. iOS 26: the same tools, chosen up front.
    static func session(for evidence: TimelineEvidence, log: TimelineToolLog) -> LanguageModelSession {
        #if compiler(>=6.4)
        if #available(macOS 27, iOS 27, *) {
            return LanguageModelSession(profile: TimelineDynamicProfile(state: TimelineProfileState(evidence: evidence), log: log))
        }
        #endif
        return LanguageModelSession(tools: tools(for: evidence, log: log), instructions: TimelineAnswerPolicy.instructions)
    }

    /// The tools named by `TimelineTools.names(for:)` for the evidence's trail, in that order.
    static func tools(for evidence: TimelineEvidence, log: TimelineToolLog) -> [any Tool] {
        TimelineTools.names(for: evidence.trail).map { name -> any Tool in
            switch name {
            case TimelineTools.counts: return TimelineCountsTool(evidence: evidence, log: log)
            case TimelineTools.photoActivity: return PhotoActivityTool(evidence: evidence, log: log)
            case TimelineTools.addedScreenshots: return AddedScreenshotsTool(evidence: evidence, log: log)
            case TimelineTools.bookings: return TimelineBookingsTool(evidence: evidence, log: log)
            default: return RedactionSummaryTool(evidence: evidence, log: log)
            }
        }
    }

    static func reason(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return ""
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is turned off in Settings."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading."
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence."
        case .unavailable:
            return "Apple Intelligence is unavailable."
        }
    }
}

@available(macOS 26, iOS 26, *)
@Generable
struct TimelineAnswerPayload {
    @Guide(description: "Two or three short sentences using only facts returned by the tools.")
    var answer: String
    @Guide(description: "Which kinds of evidence the answer used.")
    var evidenceKinds: [PayloadEvidenceKind]
}

@available(macOS 26, iOS 26, *)
@Generable
enum PayloadEvidenceKind {
    case photoActivity
    case screenshot

    var kind: EvidenceKind {
        switch self {
        case .photoActivity: .photoActivity
        case .screenshot: .screenshot
        }
    }
}

#if compiler(>=6.4)
/// Mirrors `JourneyDynamicProfile`: one profile per trail, reading an immutable snapshot.
@available(macOS 27, iOS 27, *)
struct TimelineDynamicProfile: LanguageModelSession.DynamicProfile {
    let state: TimelineProfileState
    let log: TimelineToolLog

    var body: some LanguageModelSession.DynamicProfile {
        let evidence = state.snapshot
        if evidence.trail == .travel {
            LanguageModelSession.Profile {
                Instructions(TimelineAnswerPolicy.instructions)
                PhotoActivityTool(evidence: evidence, log: log)
                AddedScreenshotsTool(evidence: evidence, log: log)
                TimelineBookingsTool(evidence: evidence, log: log)
            }
        } else if evidence.trail == .photos {
            LanguageModelSession.Profile {
                Instructions(TimelineAnswerPolicy.instructions)
                PhotoActivityTool(evidence: evidence, log: log)
                TimelineCountsTool(evidence: evidence, log: log)
            }
        } else if evidence.trail == .privacy {
            LanguageModelSession.Profile {
                Instructions(TimelineAnswerPolicy.instructions)
                TimelineCountsTool(evidence: evidence, log: log)
                RedactionSummaryTool(evidence: evidence, log: log)
            }
        } else {
            LanguageModelSession.Profile {
                Instructions(TimelineAnswerPolicy.instructions)
                TimelineCountsTool(evidence: evidence, log: log)
                PhotoActivityTool(evidence: evidence, log: log)
                AddedScreenshotsTool(evidence: evidence, log: log)
            }
        }
    }
}
#endif

/// Which tools ran during one answer, in order, without repeats.
final class TimelineToolLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    func record(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        if !recorded.contains(name) { recorded.append(name) }
    }

    var names: [String] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
}

@available(macOS 26, iOS 26, *)
struct TimelineCountsTool: Tool {
    let name = "timeline_counts"
    let description = "Counts for the person's timeline: photo events, photos, screenshots, and whether Safari history is readable here."
    let evidence: TimelineEvidence
    let log: TimelineToolLog

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        log.record(name)
        return evidence.countsLine
    }
}

@available(macOS 26, iOS 26, *)
struct PhotoActivityTool: Tool {
    let name = "photo_activity"
    let description = "Photo activity bursts with dates, photo and screenshot counts, and on-device scene labels."
    let evidence: TimelineEvidence
    let log: TimelineToolLog

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        log.record(name)
        return evidence.photoLines.joined(separator: "\n")
    }
}

@available(macOS 26, iOS 26, *)
struct AddedScreenshotsTool: Tool {
    let name = "added_screenshots"
    let description = "Scrubbed text of screenshots the person added, such as bookings or receipts. Emails, codes and card numbers are already redacted."
    let evidence: TimelineEvidence
    let log: TimelineToolLog

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        log.record(name)
        return evidence.screenshotLines.joined(separator: "\n")
    }
}
@available(macOS 26, iOS 26, *)
struct TimelineBookingsTool: Tool {
    let name = TimelineTools.bookings
    let description = "Bookings found in screenshots the person added: kind, date and the first line. A booking screenshot does not prove the trip happened."
    let evidence: TimelineEvidence
    let log: TimelineToolLog

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        log.record(name)
        return evidence.bookingLines.joined(separator: "\n")
    }
}

@available(macOS 26, iOS 26, *)
struct RedactionSummaryTool: Tool {
    let name = TimelineTools.redactionSummary
    let description = "How many emails, one-time codes and card numbers were hidden in added screenshots. Counts only, no text."
    let evidence: TimelineEvidence
    let log: TimelineToolLog

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        log.record(name)
        return evidence.redactionSummary
    }
}
#endif
