import Foundation
import SwiftUI
import PastportKit

@MainActor
final class BarModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case trail = "Recent"
        case ask = "Ask"
        var id: String { rawValue }
    }

    struct QA: Identifiable { let id = UUID(); let role: String; let text: String }

    @Published var tab: Tab = .trail
    @Published var days = 90

    @Published var models: [String] = []
    @Published var model = ""            // selected — defaults to Apple Intelligence

    // This Week
    @Published var brief = ""            // the narrated digest
    @Published var movements: [LocationLeak] = []
    @Published var threads: [IntentThread] = []
    @Published var travel: [Booking] = []
    @Published var themes: [(name: String, visits: Int)] = []

    // Ask (the agent)
    @Published var log: [QA] = []
    @Published var input = ""

    @Published var status = ""
    @Published var busy = false

    private var unlocked = false
    private var visits: [Visit] = []     // cached for the agent session

    var usingApple: Bool { model == AppleFoundation.displayName }

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.unlocked = false; SessionLock.relock() }
        }
    }

    /// Pick a default model (Apple first), then tell the person about their week.
    func start() {
        Task { @MainActor in
            if demoMode {
                models = ["Demo data"]
                model = "Demo data"
                loadDemo()
                return
            }
            var list: [String] = AppleFoundation.isAvailable ? [AppleFoundation.displayName] : []
            list += (try? await Ollama.listModels()) ?? []
            models = list
            if model.isEmpty { model = list.first ?? "" }
            loadTrail()
        }
    }

    private var demoMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo")
            || ProcessInfo.processInfo.environment["PASTPORT_DEMO"] == "1"
    }

    private func loadDemo() {
        let v = DemoData.visits
        visits = v
        let s = Stats.compute(from: v)
        movements = Movements.scan(from: v)
        threads = Threads.scan(from: v, limit: 6)
        travel = Bookings.scan(from: v).filter(\.isTravel)
        themes = s.categories.prefix(6).map { (name: $0.name, visits: $0.visits) }
        brief = ""
        status = "Demo data · no history read"
    }

    private func unlockAndFetch() async -> [Visit]? {
        if !unlocked {
            status = "Waiting for Touch ID…"
            let ok = await Task.detached {
                SessionLock.ensureUnlocked(reason: "unlock your Safari browsing history", graceMinutes: 480)
            }.value
            guard ok == 0 else {
                status = ok == 2 ? "No Touch ID / passcode — history kept closed."
                                 : "Touch ID cancelled — history kept closed."
                return nil
            }
            unlocked = true
        }
        status = "Reading history…"
        let d = days
        do { return try await Task.detached { try fetchVisits(days: d, keyword: nil, limit: 300_000, hosts: []) }.value }
        catch {
            let t = "\(error)"
            status = t.lowercased().contains("operation not permitted")
                ? "Needs Full Disk Access — enable Pastport in System Settings › Privacy."
                : t
            return nil
        }
    }

    func loadTrail() {
        guard !demoMode else {
            loadDemo()
            return
        }
        Task { @MainActor in
            busy = true; defer { busy = false }
            brief = ""; movements = []; threads = []; travel = []; themes = []
            guard let v = await unlockAndFetch(), !v.isEmpty else {
                if status.isEmpty { status = "No visits in the last \(days) days." }; return
            }
            visits = v
            // All three are pure functions over the rows, and each walks up to 300k of them.
            // Run them off the main actor together or the window freezes for the whole scan.
            let scanned = await Task.detached {
                (stats: Stats.compute(from: v),
                 leaks: Movements.scan(from: v),
                 intents: Threads.scan(from: v, limit: 6),
                 booked: Bookings.scan(from: v).filter(\.isTravel))
            }.value
            let s = scanned.stats
            movements = scanned.leaks
            threads = scanned.intents
            travel = scanned.booked
            themes = s.categories.prefix(6).map { (name: $0.name, visits: $0.visits) }
            let moves = movements.map {
                "\($0.headline) → \(coord($0.lat)),\(coord($0.lng)) [\($0.mapProvider)]"
            }
            let intents = threads.map(\.digestLine)
            let prompt = Digest.prompt(
                categorySummary: Digest.ranked(s.categories.map { ($0.name, $0.visits) }, label: "CATEGORIES"),
                topSites: Digest.ranked(s.topHosts.map { ($0.host, $0.visits) }, label: "SITES"),
                movements: moves, threads: intents, days: days, instruction: nil
            )
            status = "Reading your last \(days) days on-device with \(model)…"
            let apple = usingApple, m = model
            do {
                brief = try await Task.detached {
                    apple ? try await AppleFoundation.generate(prompt: prompt)
                          : try await Ollama.generate(model: m, prompt: prompt)
                }.value
                status = ""
            } catch { status = "\(error)" }
        }
    }

    func ask() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        input = ""
        log.append(QA(role: "user", text: q))
        if demoMode {
            log.append(QA(role: "assistant", text: "Demo mode only uses fictional rows. I found a demo Airbnb movement in Paris and two demo travel commitments; no Safari history was read."))
            return
        }
        Task { @MainActor in
            busy = true; defer { busy = false }
            if visits.isEmpty { guard let v = await unlockAndFetch() else { return }; visits = v }
            let v = visits, apple = usingApple, m = model
            do {
                let reply: String
                if apple, AppleFoundation.isAvailable {
                    reply = try await HistoryAgent.ask(question: q, visits: v)
                } else {
                    let s = Stats.compute(from: v)
                    let sites = s.topHosts.prefix(15).map { "\($0.host)(\($0.visits))" }.joined(separator: ", ")
                    let categories = s.categories.map { "\($0.name):\($0.visits)" }.joined(separator: ", ")
                    let ctx = "Answer only from this person's Safari history. Top sites: \(sites). Categories: \(categories)."
                    reply = try await Ollama.generate(model: m, prompt: ctx + "\n\nQ: \(q)\nA:")
                }
                log.append(QA(role: "assistant", text: reply))
            } catch { log.append(QA(role: "assistant", text: "\(error)")) }
        }
    }

    private func coord(_ v: Double) -> String { String(format: "%.5f", v) }
}

struct BarView: View {
    @StateObject private var m = BarModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 420, height: 560)
        .onAppear { m.start() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Pastport").font(.headline)
            Text("on-device").font(.caption2.weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.tint.opacity(0.15)).foregroundStyle(.tint).clipShape(Capsule())
            Spacer()
            Menu {
                Picker("Model", selection: $m.model) {
                    ForEach(m.models, id: \.self) { Text($0).tag($0) }
                }
                Divider()
                Picker("Window", selection: $m.days) {
                    Text("7 days").tag(7); Text("30 days").tag(30)
                    Text("90 days").tag(90); Text("1 year").tag(365)
                }.onChange(of: m.days) { m.loadTrail() }
            } label: {
                Label(m.model.isEmpty ? "No model" : shortModel, systemImage: "cpu")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var shortModel: String {
        m.model == AppleFoundation.displayName ? "Apple Intelligence" : m.model
    }

    private var content: some View {
        VStack(spacing: 0) {
            Picker("", selection: $m.tab) {
                ForEach(BarModel.Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 14).padding(.vertical, 10)

            if !m.status.isEmpty {
                HStack(spacing: 6) {
                    if m.busy { ProgressView().controlSize(.small) }
                    Text(m.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.horizontal, 14).padding(.bottom, 6)
            }

            switch m.tab {
            case .trail: trail
            case .ask: ask
            }
        }
    }

    private var trail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Order is the argument. What the person is least likely to know goes first,
                // and it's the part no model touched — a deterministic headline can't be
                // wrong. The model's prose is the least trustworthy thing on screen, so it
                // goes last and starts collapsed.
                if !m.movements.isEmpty {
                    ForEach(m.movements) { MovementCard(leak: $0) }
                }
                // A flight, a hotel and a guesthouse aren't three things you did — they're
                // one trip. Grouped, because that's how a person remembers it.
                if !m.travel.isEmpty {
                    HStack {
                        Text("TRAVEL").font(.caption2.weight(.semibold))
                        Spacer()
                        Text("\(m.travel.count)").font(.caption2)
                    }.foregroundStyle(.secondary)
                    ForEach(m.travel.prefix(8)) { TravelRow(booking: $0) }
                }
                // Demoted deliberately. Bookings outnumber threads roughly 6:1 in a real
                // year, and where you went is what a person actually wants back — what
                // they were googling is context, not the product. It also holds the
                // sensitive material, so it belongs closed by default.
                if !m.threads.isEmpty {
                    DisclosureGroup {
                        VStack(spacing: 8) {
                            ForEach(m.threads) { ThreadCard(thread: $0) }
                        }.padding(.top, 6)
                    } label: {
                        Text("What you were working out · \(m.threads.count)")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                // The model's essay used to open this view. It said little the cards above
                // don't say better, and it was the surface that invented a city — so it is
                // gone from here entirely. Ask is where the model belongs.
                if !m.brief.isEmpty {
                    DisclosureGroup {
                        Text(markdown(m.brief)).font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    } label: {
                        Text("What \(m.model) made of it").font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 2)
                }
                if !m.themes.isEmpty {
                    Text("THEMES").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    FlowChips(items: m.themes.map { "\($0.name) · \($0.visits)" })
                }
                if m.brief.isEmpty && !m.busy {
                    Button("Read my week") { m.loadTrail() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
        }
    }

    private var ask: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if m.log.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ask anything, or dig in.").font(.callout.weight(.medium))
                            ForEach(["where did I go last month — and when?",
                                     "what was I reading about?",
                                     "who tracked me?"], id: \.self) { s in
                                Button { m.input = s; m.ask() } label: {
                                    Text("“\(s)”").font(.caption).foregroundStyle(.tint)
                                }.buttonStyle(.plain)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                    ForEach(m.log) { Bubble(qa: $0) }
                }.padding(14)
            }
            HStack(spacing: 8) {
                TextField("Ask about your history…", text: $m.input)
                    .textFieldStyle(.roundedBorder).onSubmit { m.ask() }
                Button { m.ask() } label: { Image(systemName: "arrow.up.circle.fill") }
                    .buttonStyle(.plain).font(.title2).foregroundStyle(.tint)
                    .disabled(m.busy || m.input.isEmpty || m.model.isEmpty)
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }.controlSize(.small)
        }.padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// Render model output as markdown. `Text(someString)` shows `**bold**` with the asterisks
/// visible, because SwiftUI only parses markdown from a literal — not from a value produced
/// at runtime. Falls back to the raw text if parsing fails.
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(text)
}

/// One commitment in a trip — a ticket, a stay, the paperwork. Denser than a card because
/// travel comes in runs: a flight, then a room, then an arrival form, over a few days.
struct TravelRow: View {
    let booking: Booking

    private var icon: String {
        switch booking.kind {
        case .ticket, .itinerary: "airplane"
        case .checkout: "creditcard"
        case .confirmation: "checkmark.seal"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.orange).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                // The page title carries the place far more often than the URL does —
                // "Wave House - Arashiyama, Japan" needs no extraction at all.
                Text(booking.title.isEmpty ? Bookings.name(for: booking.host) : booking.title)
                    .font(.callout).lineLimit(1)
                Text(booking.time.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(.quaternary.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// One stretch of "I was trying to work something out". Shows the person's own queries
/// verbatim — the point is recognition, so paraphrasing would defeat it.
struct ThreadCard: View {
    let thread: IntentThread
    @State private var expanded = false
    @State private var revealed = false
    @State private var unlocking = false

    /// One place decides how many queries show, so the button's label can't disagree
    /// with what the list actually renders.
    private var visibleQueries: Int { expanded ? thread.queries.count : 2 }

    /// A sensitive thread shows nothing — not the topic, not the count. The topic word is
    /// the disclosure, so hiding only the queries underneath it would protect nothing.
    private var locked: Bool { thread.isSensitive && !revealed }

    var body: some View {
        if locked { lockedCard } else { openCard }
    }

    private var lockedCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("A private thread").font(.callout.weight(.semibold))
                Text("Touch ID to view").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(unlocking ? "…" : "Unlock") {
                unlocking = true
                Task { @MainActor in
                    // graceMinutes 0: a fresh prompt every time. The session-wide unlock
                    // is deliberately not enough for this tier.
                    let ok = await Task.detached {
                        SessionLock.ensureUnlocked(reason: "reveal a private thread", graceMinutes: 0)
                    }.value
                    unlocking = false
                    if ok == 0 { withAnimation(.easeOut(duration: 0.18)) { revealed = true } }
                }
            }
            .buttonStyle(.bordered).controlSize(.small).disabled(unlocking)
        }
        .padding(10)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var openCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.teal)
                Text(thread.headline).font(.callout.weight(.semibold))
                Spacer()
                // Count what the card can actually show. `searchCount` counts every search
                // event; the list shows unique phrasings. Displaying "26 searches" above a
                // "show all 3 searches" button reads as a contradiction.
                Text("\(thread.queries.count) searches")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            // Queries are deduped at construction, so they're safe to identify by value.
            ForEach(thread.queries.prefix(visibleQueries), id: \.self) { q in
                Text("“\(q)”").font(.caption).foregroundStyle(.secondary)
            }
            if !thread.destinations.isEmpty {
                FlowChips(items: Array(thread.destinations.prefix(4)))
            }
            if thread.queries.count > visibleQueries || expanded {
                Button { expanded.toggle() } label: {
                    Text(expanded ? "show less" : "show all \(thread.queries.count) searches")
                        .font(.caption2)
                }.buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MovementCard: View {
    let leak: LocationLeak
    @State private var showReceipt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // This card leads the view now, so it carries the weight of a headline.
                Image(systemName: "mappin.and.ellipse").foregroundStyle(.orange)
                Text(leak.headline).font(.headline)
                Spacer()
            }
            HStack(spacing: 8) {
                // A place, not a pair of floats — read out of the URL, never guessed.
                // Coordinates are the fallback when the link carried no address.
                if let place = leak.place {
                    Text(place).font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("\(coord(leak.lat)), \(coord(leak.lng))")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Text(leak.mapProvider).font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.orange.opacity(0.18)).foregroundStyle(.orange).clipShape(Capsule())
                Spacer()
                if let url = URL(string: "https://maps.apple.com/?ll=\(leak.lat),\(leak.lng)") {
                    Link("Open in Maps", destination: url).font(.caption)
                }
            }
            Button { showReceipt.toggle() } label: {
                Text(showReceipt ? "hide the link" : "how do we know this?").font(.caption2)
            }.buttonStyle(.plain).foregroundStyle(.tertiary)
            if showReceipt {
                // The full address and the raw link live here, together: this is the
                // evidence, and it's the part you wouldn't want on screen by default.
                if let address = leak.address {
                    Text(address).font(.caption).textSelection(.enabled)
                }
                Text(leak.decodedURL).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(4)
            }
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
    }

    private func coord(_ v: Double) -> String { String(format: "%.5f", v) }
}

struct Bubble: View {
    let qa: BarModel.QA
    private var isUser: Bool { qa.role == "user" }
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(qa.text).font(.callout).textSelection(.enabled)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(isUser ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(nsColor: .textBackgroundColor)))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(isUser ? nil : RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

/// A simple wrapping row of chips.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { s in
                Text(s).font(.caption).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.tint.opacity(0.14)).clipShape(Capsule())
            }
        }
    }
}
