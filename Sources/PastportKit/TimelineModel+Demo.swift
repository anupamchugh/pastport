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
            isLocked = false
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

    /// iPhone preview of an imported Safari export, built from fictional visits. No file is read.
    public func loadDemoImport() {
        guard let importedHistory else { return }
        let reading = [ReadingListItem(title: "Slow trains across Europe", url: "https://guide.example/slow-trains"),
                       ReadingListItem(title: "How a lens is made", url: "https://news.example/lens"),
                       ReadingListItem(title: "A week in Lisbon", url: "https://guide.example/lisbon")]
        let export = SafariExportResult(visits: DemoData.visits, profiles: 1,
                                        rowsRead: DemoData.visits.count, isPartial: false, readingList: reading)
        importedHistory.load(export)
        importedHistoryActive = true
        unlocked = true; isLocked = false
        coverage = HistorySnapshot(visits: export.visits, sourceCount: 1, sourceRows: export.rowsRead,
                                   isComplete: true, sourceLabel: SafariExport.sourceLabel).scope
        importStatus = "Imported. This stays in memory on this device until you lock or leave Pastport."
        loadDemo()
        status = "Demo export · fictional visits; no file read"
    }

    /// Shows the refusal line a rejected export gives, for previews and screenshots.
    public func loadDemoImportRefusal() { importStatus = SafariExportError.unsafeArchive.description }

    /// iPhone preview of an answer with the Skeptic's review, from fictional text. No model runs.
    /// With `reviewed` false the answer is shown with the "Challenge this answer" button and no review.
    public func loadDemoSkeptic(reviewed: Bool) {
        loadDemoImport()
        let answer = "You opened 99 pages in this window, and you spent hours on guide.example."
        var turn = AskTurn(prompt: "How many pages did I open?", answer: answer, status: .answered)
        turn.note = "Apple Intelligence · on-device history evidence"
        turns = [turn]
        tab = .ask
        guard reviewed else { return }
        skepticReviews[turn.id] = .done(SkepticReview(findings: [
            SkepticFinding(issue: .unsupportedNumber, quote: "99", why: "The recorded facts do not contain this number."),
            SkepticFinding(issue: .timeOrIntentClaim, quote: "you spent", why: "A visit shows a page was opened, not that it was read or for how long."),
        ], model: .reviewed))
    }

    /// iPhone preview of the Historian's story over the fictional import. Plain facts chapters; no model runs.
    public func loadDemoHistorian() {
        loadDemoImport()
        historian = HistorianStory(chapters: HistorianPlanner.chapters(from: DemoData.visits), isRunning: false)
    }

    func loadDemoPhotos() {
        let now = Date()
        photoEvents = PhotoEvents.cluster([
            PhotoRecord(time: now, isScreenshot: false, labels: ["landscape"]),
            PhotoRecord(time: now.addingTimeInterval(60), isScreenshot: true, labels: [])
        ])
        photoStatus = "Demo photo activity · fictional records; no library read"
    }
}
#endif
