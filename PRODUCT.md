# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios and macos. Two native targets share `PastportKit` (domain) and `PastportUI` (views) through `Package.swift`:
- `PastportiOS`: iPhone and iPad, iOS 26.0, `TARGETED_DEVICE_FAMILY: "1,2"`, no Catalyst, Designed-for-iPad or XR flags (`project.yml`, PastportiOS target).
- `Pastport` (macOS 26.0): a window plus a menu-bar panel, not sandboxed because it reads Safari history with Full Disk Access (`Sources/PastportBar/App.swift:35,43`).
- A `pastport` CLI (`Sources/pastport/main.swift`).

## Users

A general audience: anyone who wants to look back at their own recent activity (when a trip was, what they booked, which page they saw) without an account, a server or a cloud. The owner's photos and bookings are a test case, not the persona.

## Product Purpose

Pastport is a private, on-device timeline of what your devices already recorded. Swift computes every fact; the on-device model only phrases a small evidence packet and must say it does not know when the evidence has no answer. iOS cannot read Safari history, and the iPhone app says so instead of faking it (`README.md`, "iPhone and iPad").

## Screens and their one job

| Screen | Platform | One job | Source |
|---|---|---|---|
| Home / Timeline | iPhone, iPad, Mac | After an explicit read, show deterministic evidence for a window | `Sources/PastportUI/Home.swift:65`, `TimelineScreen` in `PastportiOS/PastportApp.swift:57` |
| Welcome (first run) | all | Say what is closed and offer one read action | `Home.swift:5` |
| Ask | all | Answer over the in-memory evidence, streamed, with Stop | `PastportUI/AskViews.swift:6` |
| Connected tools | all | A separate assistant with up to three approved tools and no history attached | `PastportUI/ConnectedAssistantView.swift:6` |
| Mac window and menu-bar panel | Mac | Same views plus Mac-only menu items (export, model, quit) | `PastportBar/BarView.swift:9` |

iPhone tabs today are Home and Ask only (`TimelineModel.Tab`, `Sources/PastportKit/TimelineModel.swift:50-54`). Regular width shows both side by side (`PastportApp.swift:38-43`).

## Real today vs Planned

Real today:
- Photo activity (counts, screenshots counted not inspected): `Sources/PastportKit/PhotoLibraryProvider.swift`, `PhotoEvents.swift`.
- Screenshots you add, text read on device and sensitive strings replaced: `Sources/PastportKit/ScreenshotReader.swift`; picker UI `ExploreViews.swift:84,105`.
- Timeline assistant with three read-only tools: `Sources/PastportKit/TimelineAssistant.swift`.
- Safari history, threads, bookings, trackers, map links (Mac): `Sources/PastportMac/SafariHistory.swift`, `PastportKit/Bookings.swift`, `Trackers.swift`, `Movements.swift`.
- Lock and clear; iOS clears on `.background` (`PastportApp.swift:25-28`); session gate `PastportKit/SessionLock.swift`.
- Connected tools with per-request approval: `PastportKit/ConnectedAssistant.swift`.

Planned (not implemented; source: `docs/specs/2026-10-21-pastport-2.0-iphone.md` and the prototype https://claude.ai/artifact/JDQDineuNfWjuBsHv1pZUd):
- Unlock-first Timeline with 7/30/90/365-day windows and four trails (Overview, Travel, Photos, Privacy). `TimelineTrail`: not found.
- Evidence cards with "How do we know this?"; booking cards from screenshots (`BookingFromScreenshot`: not found).
- Four iPhone tabs (Timeline, Ask, Add, Privacy) and a two-pane Duo layout with a trailing tab rail (`PaneLayout`: not found).
- Optional, off-by-default Health daily totals. The HealthKit entitlement is already declared (`PastportiOS.entitlements`) though no visible iOS Health feature exists; the spec says to remove it if Health is dropped.
- Per-trail `DynamicProfile` and typed `evidenceKinds` on answers.
- The prototype's Face ID error banner, redaction bars and Privacy approval card are mock-ups; "Real" and "New" tags in the prototype mark which is which.

## Boundaries

- Read-only. Safari history is copied to a temporary location and queried read-only; Photos never download from iCloud (spec section 4).
- Approvals: Face ID or passcode before a read; Photos permission at first read; every Connected-tools call shows its arguments and destination and waits (`README.md`).
- Leaves the device: nothing from Safari history or the timeline. Connected tools (Web, Weather) may contact the services shown in each approval and receive no timeline data. The optional Foundation Lab export is an explicit JSON of counts only.
- No account, server or analytics. No money handled.
- App Review 2.5.19: demo mode and screenshot launch arguments (`--demo`, `--ask`, `--ask-empty`, `--search`) sit inside `#if DEBUG` (`PastportApp.swift:14-22`, `Home.swift:74`). Run `hidden-feature-gate` before any upload.

## On-device AI summary

- One `LanguageModelSession` per question, three read-only tools: `timeline_counts`, `photo_activity`, `added_screenshots`; typed `@Generable TimelineAnswerPayload`; answers stream, can be stopped, list tools used (`TimelineAssistant.swift`, `AskViews.swift:52-80`).
- Mac history uses a separate typed journey with a dynamic profile per focus on macOS 27 and a static one on 26 (`HistoryJourney.swift`, README).
- Numeric check: an answer is kept only when every number appears in the evidence.
- Fallback: without Apple Intelligence Ask replies with the recorded facts and a reason line (`TimelineEvidence.countsLine`, `FoundationTimelineAnswerer.reason(for:)`); evidence screenshot `docs/screenshots/fallback-apple-intelligence-not-ready-ios.png`.
- Unit tests use fakes and never call the model.

## Accessibility & Inclusion

- Reduce Motion: the code has no custom animation (no `withAnimation`, `.animation`, `repeatForever` or Reduce Motion reads in `Sources`), so nothing pulses or flashes; keep it so. Streamed text appears in place; under Reduce Motion it should appear all at once (spec section 5; not implemented as a switch).
- Dynamic Type: text styles throughout; one fixed-size glyph (`Home.swift:28`).
- VoiceOver: decorative icons are hidden and Stop has a label (`AskViews.swift:67`); 20 accessibility modifier uses in total.
- Controls: system button styles; explicit 44 pt minimums are not set in code.
- Colour is never the only signal in the prototype; in code, accents are orange, teal and tint (see DESIGN.md).

## Out of scope

Safari history import on iPhone (spec section 8; a Mac-exported scrubbed summary is the only shape considered), iCloud sync, widgets, Apple Watch, Android, uploads, signing and release. Mac-only: Ollama, CLI, menu bar. Any change to the Mac Safari reading.

## Assumptions recorded

- The base branch is `claude/spec-2026-10-21`; the 2.0 spec was written against `main` at `14cf722`.
- Screen jobs for planned tabs come from the spec table, not from code.
- The README describes a Timeline screen on iOS; the code shows it as the tab "Home". Treated as the same screen.
- Version today is 1.3.0 build 10 (`project.yml`).
