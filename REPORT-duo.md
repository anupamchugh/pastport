# Pastport 2.0: iPhone Duo lane report (2026-10-22)

Branch `claude/pastport-duo-1022` (worktree `.worktrees/pastport-duo-1022`), based on `claude/pastport-2.0` (bf7d32e).
Local commits only; nothing pushed, merged or uploaded.

## Starting state
- 2.0 spec slices done on `claude/pastport-2.0`: 1 to 16 (docs, photo read, honest copy, unlock, locked screen, trails, evidence cards, Add, Privacy, tool labels, dynamic profile, Duo layout). Not done at the start: 17 (OpenTimelineIntent), 18 (Health totals, off by default per A1), 19 (gate + report). Update: 17 and 19 were then done on this branch; 18 skipped (spec default A1).
- `.worktrees/pastport-2.0` has uncommitted work I did not touch: modified `ScreenshotReader.swift` and `main.swift`, untracked `Sources/PastportEval/TimelineEval.swift`.

## What changed for Duo
Slice 16's layout gated on a 700 pt width breakpoint, a hand-built trailing tab rail and a custom `HStack` split.
- `PaneLayout` now takes the horizontal size class (`isRegularWidth`), not a width. New pure helpers: `tabs`, `tab(for:)`, `selecting`.
- `RootView` is one system `TabView` with `.sidebarAdaptable`. The system places the bars, and on the Duo outer display they are vertical. The hand-built `TabRail` is gone. Regular width has two tabs (Timeline, Add), one per pair; selection of Ask or Privacy is kept across fold/unfold.
- Timeline + Ask and Add + Privacy use `ArrangementView` (split) on iOS 27.1, with an `HStack` fallback below that. One `NavigationStack` and one bar sit outside the arrangement (Apple: no navigation containers inside it).
- The approval-sheet label column scales with Dynamic Type (`ScaledMetric`).
- Not changed: `UIScreen`, idiom and orientation checks (none exist), `project.yml` (already iPhone and iPad only, no Catalyst or compat flags).
- Needs Xcode 27.1 (`ArrangementView` is referenced unconditionally in source).

## Tests (executed counts)
- `swift test`, full suite, on the final code: XCTest 106 executed, 0 failures; Swift Testing runs of 122 (Kit), 7 (Mac) and 2 (Eval) passed.
- `PaneLayoutTests`: 6 tests (was 3). The first four I saw fail to compile against the old API first. The last three (tab logic) I wrote together with the implementation, so I did not see them fail first.
- No UI test target exists, so nothing tests view state across a fold.
- Builds: Debug for iPhone Duo (iOS 27.1 simulator) succeeded; Release for iPhone 17 (iOS 27.0 simulator) succeeded on the first commit, and the final code builds Release for the generic iOS Simulator destination. Built settings: `SUPPORTS_MACCATALYST = NO`, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO`, `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO`, `TARGETED_DEVICE_FAMILY = 1,2`.
- `rg "UIScreen|userInterfaceIdiom|interfaceOrientation" Sources` returns nothing.

## Screenshots: `docs/shots/duo-2026-10-22/`
Folded iPhone Duo (outer display, 466 x 678 pt), light and dark, Timeline, Ask, Add, Privacy: 8 files `duo-folded-<screen>-<light|dark>.png`, taken from the final layout with `--demo` fictional data (Debug build only).
**Unfolded (inner display) shots were not captured.** The inner-display framebuffer returned black (2007 x 2853) at every attempt: right after boot, and again 10+ minutes after boot, including re-enumerating the display UUID. No simctl or Device Hub scripting for fold/unfold was found. Per the driver's instruction I stopped there.

## Hidden-feature gate (2.5.19)
- Binary (Release build): PASS, 0 hits.
- Source: 7 hits, all the visible Face ID / Touch ID "Unlock" feature (`LockedTimelineView` and `EvidenceCards` Unlock buttons, `biometricUnlock`, `Authenticating.unlock`, `SessionLock.ensureUnlocked`). Same set as the 1.3 release record. `--demo` and `--ask` remain inside `#if DEBUG`.

## Reviewer (fresh `code-reviewer` agent, read-only, twice)
- Round 1: REQUEST CHANGES. Critical: a `NavigationStack` per pane inside `ArrangementView`. Important: paired tabs rebuilt each other; forced `.horizontal` axis; fixed 88 pt label; fold-triggered lock unverified. Fixed: single stack outside the arrangement, two tabs at regular width, system split axis, `ScaledMetric`.
- Round 2 (final): **APPROVE WITH FIXES**, no critical findings. Fixed: the state-continuity comment now says exactly what survives. Left open (need the inner display to verify, listed below).
- The reviewer could not run the app.

## Owner decisions needed
- Unfolded shots: unfold `pastport-duo-1022`-style device in Device Hub and capture inner portrait and landscape. Until then the inner layout (arrangement split, merged toolbar, sidebar) is unverified at runtime.
- View state (scroll position, expanded evidence cards) resets when the size class flips. The selected tab, lock state, evidence and Ask draft survive (they live in `TimelineModel`). Hoist those into the model if that matters.
- Shared toolbar in the Timeline + Ask pair: Lock and Clear and the Answer-from menu sit together in one bar with implicit order, and only "Timeline" is titled. Consider a header per pane, and tab labels "Timeline & Ask" / "Add & Privacy".
- Does folding or unfolding send the scene through `.background` (which calls `lockAndClear`)? Test on the Duo; if so, decide a grace period.
- `Home.swift:199` fixed `width: 30` next to a `.title3` icon could clip at accessibility sizes (not changed here).
- Slice 17 done (Open Timeline intent); slice 18 (Health totals) skipped per spec default A1. HealthKit not added.
- Spec text (section 6) still names `PaneLayout.panes(for:width:)` and a trailing tab rail; update it.

## Slices 17 and 19 (added 2026-10-22)
- 17: `OpenTimelineIntent` (`supportedModes .foreground`), `TimelineModel.openTimeline()`, `SharedTimeline.model`. Tests (TimelineModelTests): cold launch stays locked and reads/authenticates nothing; an unlocked session is cleared and returns to Timeline. Caller: Shortcuts action and Siri phrase, named in RELEASE-READY.md.
- 19: `swift test` 106 XCTest, 0 failures; Swift Testing 124 Kit, 7 Mac, 2 Eval passed. Release build for iOS Simulator succeeded; build settings MACCATALYST/MAC_DESIGNED/XR_DESIGNED = NO, TARGETED_DEVICE_FAMILY = 1,2; `rg UIScreen|userInterfaceIdiom|interfaceOrientation Sources` empty. Gate: binary 0 hits; source 7 hits, all the visible Unlock feature.
- Reviewer on the slice-17 diff: APPROVE WITH FIXES. Fixed: tautological test replaced by cold-launch and unlocked-session tests; gate claim dated and scoped; all nine tools and both off-device labels named. Open: Health package details not re-read (notes say to confirm); gate to be re-run on the final archive; the intent clears an already-unlocked open session (by design).
