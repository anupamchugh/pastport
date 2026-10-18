#if DEBUG
import Foundation

/// Fictional data for previews, tests and development screenshots. Debug builds only, so
/// release builds carry no sample-data path (App Review 2.5.19).
extension TimelineModel {
    func loadDemo() {
        guard canReadHistory else {
            // iPhone and iPad: fictional photo bursts and one fictional booking screenshot.
            let base = Date(timeIntervalSince1970: 1_751_328_000)
            photoEvents = PhotoEvents.cluster([
                PhotoRecord(time: base, isScreenshot: false, labels: ["beach", "sky"]),
                PhotoRecord(time: base.addingTimeInterval(600), isScreenshot: false, labels: ["beach"]),
                PhotoRecord(time: base.addingTimeInterval(900), isScreenshot: true, labels: []),
                PhotoRecord(time: base.addingTimeInterval(-6 * 86_400), isScreenshot: false, labels: ["food"]),
            ])
            photoStatus = "Demo photo activity · fictional records; no library read"
            screenshots = [AddedScreenshot(name: "Demo booking", addedAt: base, evidence: ScreenshotScrubber.scrub([
                "Demo Stay, Paris", "Booking reference DEMO42", "Check-in Tue 1 Jul",
                "Sent to guest@example.com", "Card 4111 1111 1111 1111",
            ]))]
            status = "Demo data · no library read"
            return
        }
        let v = DemoData.visits
        visits = v
        let s = Stats.compute(from: v)
        movements = Movements.scan(from: v)
        threads = Threads.scan(from: v, limit: 6)
        travel = Bookings.scan(from: v).filter(\.isTravel)
        themes = s.categories.prefix(6).map { (name: $0.name, visits: $0.visits) }
        sites = s.topHosts
        trackerSignals = Trackers.scan(from: v)
        historyLoaded = true
        recommendedFocuses = availableFocuses
        suggestedQuestions = questions(for: .overview)
        status = "Demo data · no history read"
    }

    func loadDemoPhotos() {
        let now = Date()
        photoEvents = PhotoEvents.cluster([
            PhotoRecord(time: now, isScreenshot: false, labels: ["landscape"]),
            PhotoRecord(time: now.addingTimeInterval(60), isScreenshot: true, labels: [])
        ])
        photoStatus = "Demo photo activity · fictional records; no library read"
    }

    func appendDemoAnswer(to question: String) {
        turns.append(AskTurn(prompt: question, answer: "Fictional evidence only: the demo includes map links and travel-related pages. Those records do not establish a completed trip. No Safari history was read.", status: .answered, note: "Demo answer"))
    }
}
#endif
