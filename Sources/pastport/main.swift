import Foundation
import PastportKit

let usage = """
pastport — private, on-device analysis of your Safari browsing history.

USAGE
  pastport [command] [query...] [options]

COMMANDS
  brief             (default) Screen-Time-style recap of your last month      [local model]
                    — travelling, reading, writing, watching — no question asked
  trail [steer]     "your iPhone just left an Airbnb" — movements + GPS leaks  [local model]
  threads [steer]   what you were working out — from your own searches         [local model]
  eval              score the model: is it accurate, and does it invent?        [local model]
  watch             background agent: notify you the moment a movement appears [live]
  ask <question>    ask about your history in plain language                   [local model]
  agent <question>  tool-calling agent — drills in ("tell me more about X")    [Apple]
  recent            list recent visits                                        [SQL only]
  search <keyword>  find visits whose title/URL match                         [SQL only]
  top               most-visited sites in the window                          [SQL only]
  when              time-of-day rhythm (visits per hour)                      [SQL only]
  stats             category + top-site breakdown                             [SQL only]
  trackers          outbound interstitials / redirects / UTM (deterministic)  [SQL only]
  bookings          confirmations, itineraries, receipts you actually made    [SQL only]
  help              show this help

OPTIONS
  --days N          look back N days (default 7; brief/agent 30; threads 90)
  --limit N         max rows to pull (default 200)
  --interval N      seconds between polls in `watch` (default 300)
  --runs N          samples per case in `eval` (default 3 — models are non-deterministic)
  --model NAME      model for brief/trail/ask (default llama3.1:8b; `apple` = Apple Foundation Models)
  --grace N         reuse a Touch ID unlock for N minutes (default 480 = a workday, 0 = always)
  --relock          force a fresh Touch ID prompt and clear the grace window
  --sql             skip the model; print the raw rows only
  --raw             show unstripped URLs (query strings intact) for inspection
  -h, --help        show this help

PRIVACY
  Touch ID is required. `recent/search/top/when/stats/trackers` never touch a model.
  `brief/trail/ask/agent` run on a LOCAL model — nothing leaves this Mac.
  Query strings are stripped from every URL shown or sent (except with --raw).
"""

// ---- parse args ----
var positionals: [String] = []
var days = 7
var limit = 200
var model = "llama3.1:8b"
var sqlOnly = false
var wantHelp = false
var grace = 480          // minutes to reuse a Touch ID unlock — a workday (0 = every time)
var relock = false       // force a fresh prompt and clear the grace window
var showRaw = false      // --raw: show unstripped URLs (query strings intact)
var interval = 300       // --interval: seconds between polls in `watch`
var daysExplicit = false  // did the user pass --days? (brief/agent default to a month otherwise)
var limitExplicit = false // did the user pass --limit? (`threads` shows 12 otherwise)
var runs = 3              // --runs: samples per eval case (these models are non-deterministic)

var it = CommandLine.arguments.dropFirst().makeIterator()
while let arg = it.next() {
    switch arg {
    case "--days": if let v = it.next(), let n = Int(v) { days = max(1, n); daysExplicit = true }
    case "--limit": if let v = it.next(), let n = Int(v) { limit = max(1, n); limitExplicit = true }
    case "--interval": if let v = it.next(), let n = Int(v) { interval = max(30, n) }
    case "--runs": if let v = it.next(), let n = Int(v) { runs = max(1, n) }
    case "--model": if let v = it.next() { model = v }
    case "--grace": if let v = it.next(), let n = Int(v) { grace = max(0, n) }
    case "--relock": relock = true
    case "--sql": sqlOnly = true
    case "--raw": showRaw = true
    case "-h", "--help", "help": wantHelp = true
    default: positionals.append(arg)
    }
}

if wantHelp { print(usage); exit(0) }

let command = positionals.first ?? "brief"
let query = positionals.dropFirst().joined(separator: " ")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("pastport: \(message)\n".utf8))
    exit(1)
}

func useApple() -> Bool { model.lowercased().hasPrefix("apple") || model.lowercased() == "foundation" }
func modelName() -> String { useApple() ? AppleFoundation.displayName : model }

// ---- Step 0: biometric gate (reuses a recent unlock within --grace minutes) ----
if relock { SessionLock.relock() }
switch SessionLock.ensureUnlocked(
    reason: "unlock your Safari browsing history",
    graceMinutes: relock ? 0 : grace
) {
case 0: break
case 2: fail("no Touch ID and no passcode set — history kept closed.")
default: fail("biometric unlock cancelled or failed — history kept closed.")
}

// ---- fetch helper with a friendly Full Disk Access hint ----
func loadVisits(keyword: String?, hosts: [String] = [], fetchLimit: Int? = nil,
                anyOf: [String] = []) -> [Visit] {
    do {
        return try fetchVisits(days: days, keyword: keyword, limit: fetchLimit ?? limit,
                               hosts: hosts, anyOf: anyOf)
    } catch {
        let text = "\(error)"
        if text.lowercased().contains("operation not permitted") {
            fail("""
            can't read Safari history — this terminal needs Full Disk Access.
            Grant it in System Settings › Privacy & Security › Full Disk Access,
            enable your terminal app, quit and reopen it, then try again.
            """)
        }
        fail(text)
    }
}

let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f
}()

// ---- commands ----
switch command {
case "recent", "search":
    let keyword = command == "search" ? query : nil
    if command == "search" && query.isEmpty { fail("`search` needs a keyword.") }
    let visits = loadVisits(keyword: keyword)
    if visits.isEmpty { print("No matching visits in the last \(days) day(s)."); break }
    let title = command == "search" ? "Matches for “\(query)”" : "Recent visits"
    print("\(title) — last \(days) day(s)\n")
    for v in visits.prefix(40) {
        let label = v.title.isEmpty ? v.cleanURL : v.title
        print("  \(dateFormatter.string(from: v.time))  \(label)\n      \(showRaw ? v.url : v.cleanURL)")
    }

case "top":
    let visits = loadVisits(keyword: nil, fetchLimit: 300_000)
    if visits.isEmpty { print("No visits in the last \(days) day(s)."); break }
    var counts: [String: Int] = [:]
    for v in visits { counts[v.host, default: 0] += 1 }
    print("Top sites — last \(days) day(s)\n")
    for (host, n) in counts.sorted(by: { $0.value > $1.value }).prefix(25) {
        print("  \(String(n).padding(toLength: 5, withPad: " ", startingAt: 0)) \(host)")
    }

case "when":
    let visits = loadVisits(keyword: nil, fetchLimit: 300_000)
    if visits.isEmpty { print("No visits in the last \(days) day(s)."); break }
    var perHour = Array(repeating: 0, count: 24)
    let cal = Calendar.current
    for v in visits { perHour[cal.component(.hour, from: v.time)] += 1 }
    let peak = max(perHour.max() ?? 1, 1)
    print("When you browse — last \(days) day(s)\n")
    for h in 0..<24 {
        let bar = String(repeating: "█", count: Int((Double(perHour[h]) / Double(peak)) * 30))
        print(String(format: "  %02d:00 %@ %d", h, bar, perHour[h]))
    }

case "stats":
    let s = Stats.compute(from: loadVisits(keyword: nil, fetchLimit: 300_000))
    if s.total == 0 { print("No visits in the last \(days) day(s)."); break }
    print("Stats — last \(days) day(s) · \(s.total) visits\n")
    print("Categories")
    let maxCat = s.categories.map(\.visits).max() ?? 1
    for c in s.categories {
        let bar = String(repeating: "█", count: Int((Double(c.visits) / Double(maxCat)) * 28))
        print("  \(c.name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(bar) \(c.visits)")
    }
    print("\nTop sites")
    for h in s.topHosts { print("  \(h.visits)×  \(h.host)") }

case "trackers":
    let hits = Trackers.scan(from: loadVisits(keyword: nil, fetchLimit: 300_000))
    if hits.isEmpty { print("No outbound trackers/redirects found in the last \(days) day(s)."); break }
    print("Trackers & redirects — last \(days) day(s)\n")
    for h in hits.prefix(30) {
        print("  \(h.count)×  [\(h.kind.rawValue)]  \(h.host)\n      e.g. \(h.example)")
    }

case "brief":
    // Proactive, no question — a Screen-Time-style recap the model writes for you.
    if !daysExplicit { days = 30 }
    let visits = loadVisits(keyword: nil, fetchLimit: 300_000)
    if visits.isEmpty { print("No visits in the last \(days) day(s)."); break }
    let s = Stats.compute(from: visits)
    let leaks = Movements.scan(from: visits)
    let moves = leaks.map {
        "\($0.headline) → \(String(format: "%.5f", $0.lat)),\(String(format: "%.5f", $0.lng)) [\($0.mapProvider)]"
    }
    let intents = Threads.scan(from: visits, limit: 6).map(\.digestLine)
    if sqlOnly {
        print("Brief — last \(days) day(s) · \(s.total) visits\n")
        if !intents.isEmpty { print("Threads:"); for t in intents { print("  \(t)") }; print("") }
        if !leaks.isEmpty { print("Movements:"); for m in moves.prefix(8) { print("  \(m)") }; print("") }
        print("Top categories: \(s.categories.prefix(8).map { "\($0.name) (\($0.visits))" }.joined(separator: ", "))")
        break
    }
    let prompt = Digest.prompt(
        categorySummary: Digest.ranked(s.categories.map { ($0.name, $0.visits) }, label: "CATEGORIES"),
        topSites: Digest.ranked(s.topHosts.map { ($0.host, $0.visits) }, label: "SITES"),
        movements: moves, threads: intents, days: days,
        instruction: query.isEmpty ? nil : query
    )
    print("Your last \(days) days, read on-device by \(modelName())…\n")
    do {
        print(useApple() ? try await AppleFoundation.generate(prompt: prompt)
                         : try await Ollama.generate(model: model, prompt: prompt))
    } catch { fail("\(error)") }

case "trail", "movements":
    let leaks = Movements.scan(from: loadVisits(keyword: nil, fetchLimit: 300_000))
    if leaks.isEmpty { print("No movements/location leaks in the last \(days) day(s)."); break }
    print("Movements — last \(days) day(s) · \(leaks.count) location leak(s)\n")
    for leak in leaks.prefix(20) {
        print("  \(dateFormatter.string(from: leak.time))  \(leak.headline)")
        print("      \(String(format: "%.5f", leak.lat)),\(String(format: "%.5f", leak.lng))  [\(leak.mapProvider)]")
        if showRaw { print("      \(leak.decodedURL)") }
    }
    if sqlOnly { break }
    let prompt = Movements.narrationPrompt(leaks: leaks, instruction: query.isEmpty ? nil : query, days: days)
    print("\n— narrated on-device by \(modelName()) —\n")
    do {
        print(useApple() ? try await AppleFoundation.generate(prompt: prompt)
                         : try await Ollama.generate(model: model, prompt: prompt))
    } catch { fail("\(error)") }

case "threads":
    // Bursts only stand out against a run of history, so look back further by default.
    if !daysExplicit { days = 90 }
    let threads = Threads.scan(from: loadVisits(keyword: nil, fetchLimit: 300_000),
                               limit: limitExplicit ? limit : 12)
    if threads.isEmpty { print("No intent threads in the last \(days) day(s)."); break }
    print("Threads — last \(days) day(s) · \(threads.count) found\n")
    for thread in threads {
        print("  \(thread.headline)  ·  \(thread.searchCount) searches")
        for q in thread.queries.prefix(3) { print("      ? \(q)") }
        if !thread.destinations.isEmpty {
            print("      → \(thread.destinations.prefix(5).joined(separator: ", "))")
        }
        if sqlOnly { print(""); continue }
        // One session per thread: each gets a full 4096-token window rather than
        // sharing one (TN3193). A thread the model declines is skipped, not fatal.
        let steer = query.isEmpty ? nil : query
        if useApple() {
            if let narration = (try? await Guided.narrate(thread, instruction: steer)) ?? nil {
                print("      \(narration.intent)")
                print("      \(narration.exposure)")
            }
        } else if let text = try? await Ollama.generate(
            model: model, prompt: Threads.narrationPrompt(for: thread, instruction: steer)
        ) {
            print("      \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        print("")
    }

case "bookings":
    // The other half of travel: `threads` finds the research, this finds the commitment.
    if !daysExplicit { days = 365 }
    let found = Bookings.scan(from: loadVisits(keyword: nil, fetchLimit: 300_000))
    if found.isEmpty { print("No bookings or confirmations in the last \(days) day(s)."); break }
    print("Bookings & confirmations — last \(days) day(s) · \(found.count) found\n")
    for b in found.prefix(40) {
        print("  \(b.headline)")
        if !b.title.isEmpty { print("      \(b.title.prefix(90))") }
        if showRaw { print("      \(b.url)") }
    }

case "eval":
    // Score the narration layer against facts we already know are true. This is the
    // regression net for the "bustling city of Delhi" class of failure.
    if !daysExplicit { days = 90 }
    let visits = loadVisits(keyword: nil, fetchLimit: 300_000)
    if visits.isEmpty { print("No visits in the last \(days) day(s)."); break }
    let stats = Stats.compute(from: visits)
    let evalThreads = Threads.scan(from: visits, limit: 3)
    let evalLeaks = Movements.scan(from: visits)

    print("Eval — \(modelName()) · last \(days) day(s) · \(runs) run(s) per case\n")
    let results = await Eval.run(
        stats: stats, threads: evalThreads, leaks: evalLeaks, runs: runs,
        narrate: { p in
            useApple() ? try await AppleFoundation.generate(prompt: p)
                       : try await Ollama.generate(model: model, prompt: p)
        }
    )
    guard !results.isEmpty else { print("Not enough signal in this window to score."); break }

    for r in results {
        let mark = r.correct == r.runs ? "PASS" : (r.correct == 0 ? "FAIL" : "FLAKY")
        print("  \(mark)  \(r.id)  [\(r.capability)]  \(r.correct)/\(r.runs)")
        print("      expected: \(r.truth)")
        print("      answered: \(r.sample.replacingOccurrences(of: "\n", with: " ").prefix(120))")
        if !r.inventions.isEmpty {
            print("      INVENTED: \(r.inventions.joined(separator: ", "))")
        }
        print("")
    }
    let totalRuns = results.reduce(0) { $0 + $1.runs }
    let correct = results.reduce(0) { $0 + $1.correct }
    let clean = results.reduce(0) { $0 + $1.clean }
    print("  factual   \(correct)/\(totalRuns)")
    print("  grounded  \(clean)/\(totalRuns)  (answers that invented nothing)")
    let flaky = results.filter(\.unstable).map(\.id)
    if !flaky.isEmpty { print("  unstable  \(flaky.joined(separator: ", "))  (flipped across runs)") }

case "watch":
    print("Watching Safari history — on-device, Ctrl-C to stop.")
    print("(polling every \(interval)s · movements, threads and bookings)\n")

    // One store per detector, one notification path, one loop. Adding a fourth detector
    // is a line here, not another copy of this block.
    let stores = (movements: SeenStore("seen-movements.json"),
                  threads: SeenStore("seen-threads.json"),
                  bookings: SeenStore("seen-bookings.json"))

    /// Announce whatever is new. Seeding on a first run is silent — nobody wants a burst
    /// of notifications about history they already lived through.
    func announce<F: Finding>(_ findings: [F], _ store: SeenStore, label: String) {
        let (new, wasSeeded) = store.fresh(from: findings)
        if wasSeeded {
            print("  seeded \(findings.count) existing \(label) — will alert only on new ones.")
            return
        }
        for finding in new {
            print("  \(finding.headline) → \(finding.notificationBody)")
            notifyUser(title: finding.headline, body: finding.notificationBody)
        }
    }

    while true {
        let visits = loadVisits(keyword: nil, fetchLimit: 300_000)
        announce(Movements.scan(from: visits), stores.movements, label: "movement(s)")
        announce(Threads.scan(from: visits), stores.threads, label: "thread(s)")
        announce(Bookings.scan(from: visits), stores.bookings, label: "booking(s)")
        try? await Task.sleep(for: .seconds(interval))
    }

case "ask":
    if query.isEmpty { fail("`ask` needs a question.") }
    // Match any content word in the question, and pull from the whole window rather than
    // the 200-row default — a question about a year of history was previously answered
    // from 200 rows, of which the model then saw 60.
    let terms = keywordsFrom(query)
    var visits = loadVisits(keyword: nil, fetchLimit: 300_000, anyOf: terms)
    if visits.isEmpty { visits = loadVisits(keyword: nil, fetchLimit: 300_000) }
    if visits.isEmpty { print("No visits in the last \(days) day(s)."); break }
    if sqlOnly {
        for v in visits.prefix(40) {
            print("  \(dateFormatter.string(from: v.time))  \(v.title.isEmpty ? v.cleanURL : v.title)")
        }
        break
    }
    // Rank before capping, so the 60 lines the model sees are the 60 most relevant.
    let ranked = rankVisits(visits, matching: terms, limit: 60)
    let prompt = analysisPrompt(visits: ranked, question: query, days: days)
    print("Analyzing \(visits.count) matching visits (top \(ranked.count) by relevance) with \(modelName())…\n")
    do {
        print(useApple() ? try await AppleFoundation.generate(prompt: prompt)
                         : try await Ollama.generate(model: model, prompt: prompt))
    } catch { fail("\(error)") }

case "agent":
    if !daysExplicit { days = 30 }   // give the agent a month to drill into
    let question = query.isEmpty ? "What are my main interests, and is anything tracking me?" : query
    let visits = loadVisits(keyword: nil, fetchLimit: 300_000)
    print("On-device agent (Apple Foundation Models, tool-calling) — \(question)\n")
    do {
        print(try await HistoryAgent.ask(question: question, visits: visits))
    } catch { fail("\(error)") }

default:
    fail("unknown command “\(command)”. Run `pastport help`.")
}
