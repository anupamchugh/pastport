import Foundation

/// A Screen-Time-style life recap the model writes *for* you — no question asked. It takes the
/// deterministic signals (category mix, top sites, movements) and lets the on-device model name
/// the life-themes it sees: travelling, reading, writing/blogging, watching, building.
public enum Digest {

    /// Rank and describe in Swift, so the prompt carries an ordering rather than a table of
    /// figures to sort. The eval measured both backends at 0/3 on arithmetic and 2/3 on
    /// picking a maximum from 24 rows — handing them eight counts and asking for a summary
    /// is asking for the one thing they cannot do. Words they can repeat; sums they cannot.
    public static func ranked(_ items: [(name: String, count: Int)], label: String) -> String {
        let sorted = items.sorted { $0.count > $1.count }
        guard let top = sorted.first else { return "" }
        let rest = sorted.dropFirst().prefix(3).map(\.name)
        let tail = rest.isEmpty ? "" : ", then \(rest.joined(separator: ", "))"
        return "\(label) (already ranked — do not re-count or re-rank): \(top.name) is the "
            + "largest by a clear margin\(tail)."
    }

    public static func prompt(
        categorySummary: String,
        topSites: String,
        movements: [String],
        threads: [String] = [],
        days: Int,
        instruction: String?
    ) -> String {
        let moves = movements.isEmpty
            ? "(none found in the window)"
            : movements.prefix(8).joined(separator: "\n")
        let intents = threads.isEmpty
            ? "(none found in the window)"
            : threads.prefix(6).joined(separator: "\n")
        let steer = instruction.map { "\nThe person also asked you to: \($0)\n" } ?? ""
        return """
        You read a person's own Safari history, on-device, and write them a short recap — like
        Apple's Screen Time weekly report, but about their life rather than their screen time.
        Do NOT ask them anything; just tell them what they were up to over the last \(days) days.

        Write AT MOST 3 short sections, each a bold headline and two sentences. This is read in
        a small window — a five-section essay is worse than three tight paragraphs, so leave
        out the weakest theme rather than covering everything.
        Write in the second person ("Last month you…"). Use ONLY the signals below. Where you
        infer, say you are inferring. Lead with the threads and movements — those are the parts
        the person is least likely to already know; category counts they can guess. Never name a
        place, company, or product that is not written verbatim below. State only what the
        signal says: "left an app toward a map" is not "checked in", and a search is not a trip.
        \(steer)
        THINGS YOU WERE WORKING OUT (from your own searches):
        \(intents)

        MOVEMENTS (place + time found in URLs):
        \(moves)

        \(categorySummary)

        \(topSites)
        """
    }
}
