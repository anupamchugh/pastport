# Pastport

**Your browser history knows where you live. It's been writing it down in plain text.**

A native macOS app and CLI that reads *your own* Safari history and tells you what it reveals — entirely on-device, behind Touch ID, with no network calls at all.

```
📍 Your iPhone left Airbnb on Saturday 10:07 AM
   Fitzroy, Melbourne                         [Open in Maps]  how do we know this?
```

That line is not a guess. Some sites route outbound taps through a "You're leaving…" interstitial, and the destination is carried in the URL — sometimes as an exact GPS coordinate *and* a full postal address, both of which land in `History.db` verbatim. Pastport decodes what is already there.

No model produced that headline. It's a regex and a string.

---

## What it finds

| | what it detects | how |
|---|---|---|
| **Movements** | a coordinate + timestamp sitting in a URL | percent-decode ×3, then a coordinate regex requiring ≥4 decimal places |
| **Threads** | what you were *working out* — a burst of related searches | term frequency ÷ days-spanned. A word searched 1,600× a year is a habit; 3× in an afternoon is a decision |
| **Bookings** | what you *committed to* — confirmations, itineraries, receipts | URL and title shape: `/confirmation`, `/itinerary`, `/eticket`, `booking_id=` |
| **Trackers** | who routed your clicks | interstitials, redirects, `utm_`, `fbclid=` |

**No detector contains a brand name.** `www.example.com` → `Example` is derived at runtime. A booking confirmation on a guesthouse nobody has heard of classifies exactly like one on a major airline — because the code matches what a page *is*, never who runs it.

---

## The interesting part: we measured whether the model lies

`brief` once narrated a coordinate as *"the bustling city of Delhi."* It was not Delhi. There is no geocoder anywhere in this package — the model invented it.

That bug class has a detector now, because **hallucination here is mechanically checkable**: every claim the model can make is either in the rows you handed it or invented. No labels, no human graders, no judge model. Set membership.

```
$ pastport eval --runs 3

  capability                Apple Foundation   llama3.1:8b
  lookup                          3/3              3/3
  compare dates                   3/3              3/3
  negation                        3/3              3/3
  abstain (say what it can't know) 3/3             3/3
  summarise given text            2/3              3/3
  argmax over 24 rows             2/3              2/3
  arithmetic                      0/3              0/3
  ────────────────────────────────────────────────────────
  factual                        16/21            17/21
  grounded                       18/21            15/21
```

**Neither model can add a column of five numbers.** Not rounding error — against a true `56259`, one returned `23466`, `22066`, `44871` across three runs; the other returned `65259` and `65559`. Both with total confidence.

And the counterintuitive one: **the bigger model is more accurate but less grounded.** Asked to summarise a thread about a film, `llama3.1:8b` named an actor who starred in it — correct about the world, absent from the evidence. For a tool whose promise is *"this is what YOUR history says"*, world-knowledge bleed is a defect.

So the architecture is: **SQL computes, the model phrases.** Every number you see comes from Swift. The model only turns proven facts into a sentence, inside a `@Generable` type that has no field for a place name — so constrained sampling gives it nowhere to invent one.

---

## Privacy

- **Nothing leaves the Mac.** No network calls. Models are Apple Foundation Models (on-device) or Ollama (localhost).
- **Touch ID** gates every read, fail-closed.
- **Read-only.** The live `History.db` is copied to a temp dir and the copy is queried; the original is never opened for write.
- **Query strings stripped** from every URL displayed or sent to a model, unless you pass `--raw`.
- **Sensitive threads are gated.** Health, legal and intimate topics render as *"A private thread — Touch ID to view"*, showing neither the topic nor the count, because the topic word is the disclosure.

---

## Install

Requires macOS 26 (Apple Intelligence optional — the deterministic commands need no model at all).

```bash
git clone https://github.com/anupamchugh/pastport
cd pastport
swift build -c release
./install.sh          # builds and installs the .app
# Safe synthetic UI preview; this never reads Safari history.
./install.sh --demo
```

Grant Full Disk Access to your terminal (for the CLI) or to the app — Safari's history is TCC-protected, and no tool can grant that for you.

## Use

```bash
pastport recent            # what you looked at
pastport threads           # what you were working out
pastport bookings          # what you committed to
pastport trail             # coordinates leaked into URLs
pastport trackers          # who routed your clicks
pastport when              # your rhythm, by hour
pastport ask "what did I book and where did I stay"
pastport eval --runs 3     # is the model telling the truth?
pastport watch             # notify me when something new appears
```

Everything except `ask`, `brief` and `eval` runs with no model whatsoever.

---

## Contributing

**One rule matters more than the rest: detectors match wire-format shape, never brand names.**

A confirmation page looks the same everywhere. If a PR adds a domain list, it will rot the moment a site rebrands — and it will silently fail for every site not on it. Match `/confirmation`, not a company.

Good first contributions:

- **Chrome and Firefox.** Both keep history in SQLite. Swap `Core.historyDatabases()` and every detector works unchanged.
- **A new detector.** ~50 lines conforming to `Finding`, plus tests. Job hunting, subscriptions, price tracking.
- **New eval cases.** The harness exists; more capability probes are cheap.
- **New tracker or booking signals** — pure data.

Every test builds synthetic `Visit` values, so **you never need a browsing history — yours or anyone's — to contribute.**

```bash
swift test        # 55 tests, no personal fixtures, no network
```

## Download a signed release

Download the notarized DMG or ZIP from the [latest GitHub release](https://github.com/anupamchugh/pastport/releases/latest). On first launch, grant Pastport Full Disk Access in System Settings → Privacy & Security → Full Disk Access. The app is intentionally unsandboxed because Safari's protected history database requires that permission.

## License

MIT.
