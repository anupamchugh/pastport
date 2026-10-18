# Pastport rehaul — Mac + iPhone, one core (2026-10-19)

Started from the Gemini draft in `~/Desktop/workspace/.nightly/specs/2026-10-19-pastport-rehaul.md`.
Every claim below was re-checked against `main` at `cfac9f1`. Claims the draft made about files
that are not tracked in git (`AGENTS.md`, `CLAUDE.md`, `docs/foundation-lab.md`, `docs/plans/`)
were dropped. No prototype exists for Pastport (`.nightly/PROTOTYPES.md` has no row), so this
spec carries a one-page direction instead.

## Direction (one page)

Pastport is a private, on-device timeline of what your devices already recorded: pages you
opened, photo bursts, screenshots of bookings. Swift computes every fact; the on-device model
only phrases a small evidence packet and must say it does not know when the packet has no answer.

- **Mac** keeps everything it does today: Safari history (Full Disk Access, not sandboxed),
  research threads, travel pages, trackers, map links, photo activity, the history assistant,
  connected tools, Foundation Lab export, the CLI, the menu-bar item.
- **iPhone/iPad** builds a timeline from what iOS allows: Photos activity (screenshots counted,
  never inspected), screenshots the person adds (OCR, scrubbed), and an assistant over that
  timeline. iOS does not let apps read Safari history, and the app says so on the timeline.
- Both lock and clear on demand. iOS also clears when the app goes to the background
  (the Mac clears on screen lock, `BarView.swift:68`).

## 1. Who it is for, and each screen's one job

A general audience who want to look back at their own recent activity without an account or
a server.

| Screen | Platforms | One job |
|---|---|---|
| Explore / Timeline | Mac window + menu bar, iPhone, iPad | Read local sources when the person chooses, then show deterministic evidence. |
| Ask | all | Answer questions over the in-memory evidence, streamed, with Stop and a tools-used row. |
| Connected tools | all | A separate assistant with up to three approved tools and no history attached (`ConnectedAssistant.swift:88-114`). |

## 2. Screens

**Explore (Mac).** Today `BarView.trail` (`BarView.swift:474-534`): focus grid
(`HistoryFocus`, `HistoryJourney.swift:4-22`), selected evidence (`BarView.swift:536-569`),
suggested questions, photo activity disclosure. Data from `fetchHistorySnapshot`
(`Core.swift:237-291`), `Stats`, `Movements`, `Threads`, `Bookings`, `Trackers`,
`PhotoLibraryProvider` (`PhotoLibraryProvider.swift:23-51`) and `PhotoEvents.cluster`
(`PhotoEvents.swift:43-78`). Empty and error copy already exists (`BarView.swift:52, 84, 180, 201, 269`).
Rehaul: same content, rendered from shared `PastportUI` views, plus a "Screenshots you added"
section (new, over the existing `ScreenshotReader`, `ScreenshotReader.swift:44-93`).

**Timeline (iOS).** New screen on the same model. Shows a "Safari history stays on your Mac"
card (iOS cannot read it), photo activity (same provider; Photos exists on iOS), and screenshots
the person adds with the photo picker, shown as scrubbed lines with the redaction count and
kind. Window picker (7, 30, 90, 365 days, all). Lock & clear in the toolbar.

**Ask.** Today `BarView.ask` (`BarView.swift:571-607`) shows bubbles with no Stop and no tool
row; `ConnectedAssistantView` has Cancel. Rehaul: a shared turn list with the prompt, the
streamed answer, a "Tools used" row and a status (answering, answered, stopped, failed), and a
Send/Stop composer. On the Mac, answers over history come from `HistoryJourney` (validated
streaming, `HistoryJourney.swift:144-163`), whose receipt already lists tool calls
(`JourneyReceipt.toolCalls`, `HistoryJourney.swift:28`). On iOS, answers come from a new
`TimelineAssistant` over photo events and added screenshots. Without Apple Intelligence the Mac
history path falls back to `AskWorkflow.evidence` (deterministic text, `AskWorkflow.swift:27`)
and iOS falls back to a deterministic timeline summary. Never an empty or invented answer.

**Connected tools.** Unchanged behaviour (`ConnectedAssistant.swift:327-522`,
`ConnectedAssistantView.swift`). The model moves from `ObservableObject` to `@Observable` and the
view moves to `PastportUI`, so iOS gets it too.

## 3. On-device AI

- History (Mac): `HistoryJourney` + `JourneyRuntime`, typed `JourneyAnswerPayload` sections,
  validated by `HistoryJourneyValidation.allowsNarrative` (`HistoryJourney.swift:406-438`).
  Unchanged.
- Timeline (iOS; also the Mac's fallback when no history is read): new `TimelineAssistant`.
  One `LanguageModelSession` per question with three read-only tools over the in-memory
  `TimelineEvidence`: `photo_activity`, `added_screenshots`, `timeline_counts`. Output is a
  `@Generable TimelineAnswerPayload { answer: String }`, streamed as partials. Code decides
  counts, dates and which screenshot text is eligible (only scrubbed text the person added);
  the model decides which tool to call and the wording. The final text passes the same
  number-subset check as history answers; a failing answer is replaced by the deterministic
  summary.
- Seam: a `TimelineAnswering` protocol. Unit tests use a fake and never call the model.
- Fallback: when `SystemLanguageModel.default.availability` is not `.available`, the
  deterministic summary, with a one-line reason.

## 4. Data and safety

- Read-only everywhere. The Safari DB is copied, then queried (`Core.swift:194-217`); Photos
  never downloads from iCloud; screenshot text is scrubbed before any display or model use
  (`ScreenshotReader.swift:95-124`).
- Approval: Touch ID / Face ID before history, photos and private threads (`SessionLock`); each
  connected tool call needs Allow Once (`ConnectedAssistant.swift:117-165`).
- No money is handled.
- 2.5.19: the `--demo` / `PASTPORT_DEMO` switch (`BarView.swift:65-66`) moves inside
  `#if DEBUG`; Ollama (localhost) becomes Mac-only code, so the iOS binary carries no localhost
  client. The gate runs before the report.

## 5. Accessibility

No flashing, pulsing or blinking; the one animation (`BarView.swift:700`) honours Reduce Motion.
Text styles only (Dynamic Type). The Send/Stop icon buttons get labels; locked thread cards
combine into one VoiceOver element.

## 6. iOS 27 / iPhone Duo

Layout from `horizontalSizeClass` and container width only; no `UIScreen.main`, idiom or
orientation (none exist today). iOS target: `supportedDestinations: [iphone, ipad]`,
`TARGETED_DEVICE_FAMILY: "1,2"`, no Catalyst, Designed-for-iPad or XR flags.

## 7. Architecture and slices

SwiftPM is the single source; `project.yml` links its products.

- `PastportKit` (macOS 26 + iOS 26): domain, detectors, sources as protocols
  (`HistorySource`, `PhotoLibraryReading`, `Authenticating`), AI sessions, and the shared
  `@Observable` `TimelineModel` (was `BarModel`, `BarView.swift:8-386`).
- `PastportMac` (macOS only): the `/usr/bin/sqlite3` Safari reader and `osascript`
  notifications (`Core.swift:51-68, 164-171, 194-347`), and the Ollama client.
- `PastportUI` (both): shared SwiftUI views; no AppKit or UIKit, no I/O.
- Apps: `Pastport` (Mac, `Sources/PastportBar`), `PastportiOS` (`Sources/PastportiOS`), and
  the `pastport` CLI.

Slices, one commit each:

1. **Spec** (this file).
2. **Core goes cross-platform.** Move Process, osascript and Ollama into `PastportMac`; add
   `HistorySource` and `Authenticating`; `SessionLock` and `Verticals` stop using
   `homeDirectoryForCurrentUser`. Check: `swift test` green with an executed count;
   `PastportKit` compiles for the iOS Simulator.
3. **Observable model + shared UI.** `TimelineModel` and `ConnectedAssistant` become
   `@Observable`; Ask gets turns with Stop and tools used; a screenshots section; AppKit stays
   in the Mac app (screen-lock observer, Quit; the save panel becomes `fileExporter`). Check:
   the moved `PrivacyStateTests` plus new tests for Stop and tools used, failing first.
4. **Timeline assistant.** `TimelineAssistant`, `TimelineEvidence` and the fallback. Check:
   tests with a fake model for streaming, Stop, fallback and the number check.
5. **iOS target + Mac app on shared views.** Check: Mac build, launch and screenshots; iPhone 17
   simulator build, launch and screenshots, light and dark, in `screenshots/2026-10-19/`.
6. **Gate + report.**

## 8. Out of scope; routine calls made without the owner

- HealthKit day summaries on the timeline: not built tonight. Health stays available as a
  Connected tool (`ConnectedAssistant.swift:103-109`). Follow-up.
- Importing a Mac history snapshot on iPhone: not built. It would move browsing history between
  devices and needs its own privacy design.
- Booking detection from screenshot text: screenshots show scrubbed text and kind only.
- Replacing `/usr/bin/sqlite3` with the SQLite C API: not needed for iOS (there is no Safari DB
  there), so the existing tested reader moves unchanged.
- Signing, notarization, upload, push: owner only.
