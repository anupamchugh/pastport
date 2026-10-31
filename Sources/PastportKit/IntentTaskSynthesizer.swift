import Foundation

/// A concrete action item synthesized from a person's browsing intent burst or booking milestones.
public struct IntentTask: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let title: String
    public let reason: String
    public let isMissingGap: Bool
    public let actionURL: String?

    public init(id: UUID = UUID(), title: String, reason: String, isMissingGap: Bool = false, actionURL: String? = nil) {
        self.id = id
        self.title = title
        self.reason = reason
        self.isMissingGap = isMissingGap
        self.actionURL = actionURL
    }
}

/// A structured action blueprint synthesized from an IntentThread and relevant timeline commitments.
public struct IntentActionPlan: Sendable, Codable, Equatable {
    public let topic: String
    public let summary: String
    public let tasks: [IntentTask]
    public let readingTopics: [String]

    public init(topic: String, summary: String, tasks: [IntentTask], readingTopics: [String]) {
        self.topic = topic
        self.summary = summary
        self.tasks = tasks
        self.readingTopics = readingTopics
    }
}

/// Synthesizes grounded, actionable plans from on-device browsing bursts (`IntentThread`)
/// and identifies missing gaps between plans and confirmed commitments (`Booking`).
public final class IntentTaskSynthesizer: Sendable {
    public init() {}

    /// Generates a deterministic action plan from an intent thread and existing bookings.
    public func synthesizePlan(thread: IntentThread, existingBookings: [Booking] = []) -> IntentActionPlan {
        let topic = thread.term.capitalized
        let allKeywords = ([thread.term] + thread.related + thread.queries)
            .joined(separator: " ").lowercased()

        var tasks: [IntentTask] = []
        var readingTopics: [String] = [thread.term] + thread.related

        let isTravelIntent = isTravel(keywords: allKeywords, thread: thread, bookings: existingBookings)
        let isTechIntent = isTechnical(keywords: allKeywords)

        if isTravelIntent {
            // Check for travel commitments & missing gaps
            let travelBookings = existingBookings.filter { $0.isTravel }
            let hasFlight = travelBookings.contains { $0.title.lowercased().contains("flight") || $0.title.lowercased().contains("ticket") || $0.title.lowercased().contains("eticket") || $0.kind == .ticket }
            let hasHotel = travelBookings.contains { $0.title.lowercased().contains("hotel") || $0.title.lowercased().contains("stay") || $0.title.lowercased().contains("ryokan") || $0.title.lowercased().contains("room") || $0.title.lowercased().contains("resort") }

            if hasFlight && !hasHotel {
                tasks.append(IntentTask(
                    id: deterministicUUID(seed: "\(thread.term)-missing-hotel"),
                    title: "Reserve accommodation in \(topic)",
                    reason: "Flight is booked, but no confirmed hotel or stay was detected in your history.",
                    isMissingGap: true,
                    actionURL: "https://booking.com/search?ss=\(thread.term)"
                ))
            } else if !hasHotel && !hasFlight {
                tasks.append(IntentTask(
                    id: deterministicUUID(seed: "\(thread.term)-explore-stay"),
                    title: "Compare accommodation options in \(topic)",
                    reason: "Research burst detected multiple stay inquiries.",
                    isMissingGap: false,
                    actionURL: nil
                ))
            }

            tasks.append(IntentTask(
                id: deterministicUUID(seed: "\(thread.term)-transit"),
                title: "Check local transit, airport transfers and rail passes for \(topic)",
                reason: "Co-occurring queries referenced transportation and itineraries.",
                isMissingGap: false,
                actionURL: nil
            ))

            tasks.append(IntentTask(
                id: deterministicUUID(seed: "\(thread.term)-prep"),
                title: "Review entry requirements, tickets and packing list for \(topic)",
                reason: "Proactive travel preparation checklist.",
                isMissingGap: false,
                actionURL: nil
            ))
        } else if isTechIntent {
            tasks.append(IntentTask(
                id: deterministicUUID(seed: "\(thread.term)-prototype"),
                title: "Build isolated spike or prototype for \(topic)",
                reason: "Concentrated technical search indicates architectural design phase.",
                isMissingGap: false,
                actionURL: nil
            ))

            tasks.append(IntentTask(
                id: deterministicUUID(seed: "\(thread.term)-docs"),
                title: "Review official documentation and test coverage for \(topic)",
                reason: "Grounded engineering workflow checklist.",
                isMissingGap: false,
                actionURL: thread.destinations.first.map { "https://\($0)" }
            ))

            readingTopics.append(contentsOf: ["Architecture", "Testing", "Performance"])
        } else {
            tasks.append(IntentTask(
                id: deterministicUUID(seed: "\(thread.term)-research-review"),
                title: "Review shortlisted options for \(topic)",
                reason: "Multiple related queries detected in your recent browsing.",
                isMissingGap: false,
                actionURL: nil
            ))

            tasks.append(IntentTask(
                id: deterministicUUID(seed: "\(thread.term)-decision"),
                title: "Make decision on \(topic) and record next steps",
                reason: "Finalize findings before the research window goes stale.",
                isMissingGap: false,
                actionURL: nil
            ))
        }

        let summary = "Identified \(tasks.count) actionable steps for \(topic) based on \(thread.searchCount) searches across \(thread.destinations.count) sites."

        return IntentActionPlan(
            topic: thread.term,
            summary: summary,
            tasks: tasks,
            readingTopics: Array(Set(readingTopics))
        )
    }

    /// When Apple Foundation Models are enabled and ready on-device, refines the action plan
    /// using on-device inference, while remaining strictly grounded in the thread's queries.
    public func refineWithFoundationModel(
        plan: IntentActionPlan,
        thread: IntentThread
    ) async -> IntentActionPlan {
        guard AppleFoundation.isReady else { return plan }
        let prompt = """
        Given this personal browsing intent thread:
        Topic: \(thread.term)
        Queries:
        \(thread.promptLines)

        Existing proposed tasks:
        \(plan.tasks.map { "- \($0.title)" }.joined(separator: "\n"))

        Suggest 1 additional high-value preparation task in plain English as a single line.
        """
        guard let output = try? await AppleFoundation.generate(prompt: prompt),
              !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return plan
        }
        let cleanTask = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[-*•]\\s*", with: "", options: .regularExpression)
        var updatedTasks = plan.tasks
        updatedTasks.append(IntentTask(
            id: deterministicUUID(seed: "\(thread.term)-ai-refinement"),
            title: cleanTask,
            reason: "Synthesized on-device by Apple Foundation Models from your search thread.",
            isMissingGap: false,
            actionURL: nil
        ))
        return IntentActionPlan(
            topic: plan.topic,
            summary: plan.summary,
            tasks: updatedTasks,
            readingTopics: plan.readingTopics
        )
    }

    // MARK: - Classification Helpers

    private func isTravel(keywords: String, thread: IntentThread, bookings: [Booking]) -> Bool {
        if bookings.contains(where: { $0.isTravel }) { return true }
        let travelWords = ["hotel", "flight", "ryokan", "shinkansen", "airline", "travel", "trip", "tour", "airport", "stay", "visa", "itami", "haneda", "narita"]
        return travelWords.contains { keywords.contains($0) }
    }

    private func isTechnical(keywords: String) -> Bool {
        let techWords = ["swift", "metal", "shader", "pipeline", "code", "compiler", "api", "git", "framework", "xcode", "endpoint", "architecture", "algorithm"]
        return techWords.contains { keywords.contains($0) }
    }

    private func deterministicUUID(seed: String) -> UUID {
        var hash = UInt64(5381)
        for byte in seed.utf8 {
            hash = 127 * (hash & 0x00ffffffffffffff) + UInt64(byte)
        }
        let u1 = UInt32(truncatingIfNeeded: hash)
        let u2 = UInt16(truncatingIfNeeded: hash >> 32)
        let u3 = UInt16(truncatingIfNeeded: hash >> 48)
        return UUID(uuid: (
            UInt8(u1 & 0xff), UInt8((u1 >> 8) & 0xff), UInt8((u1 >> 16) & 0xff), UInt8((u1 >> 24) & 0xff),
            UInt8(u2 & 0xff), UInt8((u2 >> 8) & 0xff),
            0x40 | UInt8(u3 & 0x0f), UInt8((u3 >> 8) & 0xff),
            0x80, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07
        ))
    }
}
