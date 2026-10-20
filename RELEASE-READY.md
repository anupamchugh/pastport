# Pastport 1.3.0 (10) — release-ready (not uploaded)

Local only. Nothing was uploaded, signed in, or sent to App Store Connect.
Head: `25e0900` on `main` (rehaul merged by fast-forward from `claude/pastport-rehaul` 67f878b).

## What's in it
- Native iPhone and iPad app on the shared core (no Mac Catalyst, no Designed-for-iPad/visionOS).
- Mac menu-bar app rebuilt on the same shared timeline model and views.
- Timeline from photo activity and screenshots you add (iOS); Safari history on the Mac only.
- Ask: facts come from data, wording from Apple's on-device model; if Apple Intelligence is off,
  downloading or unsupported, Ask shows the recorded facts and says why.
- Added in release prep: app icons (iOS + Mac), `PrivacyInfo.xcprivacy` (both), Mac app category,
  "1 photo / 2 photos" grammar.
- Demo data is Debug-only (not in any Release binary).

## Tests and builds (iOS 27.1 / macOS 27.0 SDKs, Xcode 27.1)
- `swift test`: **98 XCTest + 61 Swift Testing executed, 0 failures.**
- Mac Release, iOS Release, both archives: succeeded, **no code warnings** (only the harmless
  "AppIntents metadata extraction skipped" tool note).
- No test calls the model; Foundation Models paths use fakes. The availability-reason wording has its own test.

## Foundation Models
- Gate: `SystemLanguageModel.default.availability` is checked before every session.
- Off / downloading / ineligible / failed / answer not matching the facts → the facts answer plus the reason.
- Runtime proof: on the iOS 27 simulator (model not ready) Ask settled on the facts answer with
  "Apple Intelligence is still downloading." Screenshot: `docs/screenshots/ios-ask.png`.

## Walkthrough
`docs/screenshots/`: `mac-explore.png`, `mac-ask.png` (Mac, demo data), `ios-timeline.png`, `ios-ask.png` (iPhone 17 Pro, iOS 27.0 simulator).
The dedicated simulators were shut down and deleted.

## Findings and fixes
| Check | Finding | Result |
|---|---|---|
| release-review / distribution | No app icon on either target (iOS upload would fail) | Fixed: icon asset catalogs |
| privacy-manifests | No `PrivacyInfo.xcprivacy` | Fixed: added to both targets (no tracking, no collected data; UserDefaults CA92.1; Mac file timestamp 3B52.1) |
| release-review | Mac: no App Category warning | Fixed: `public.app-category.productivity` |
| UX | "1 photos · 1 screenshots" | Fixed |
| build | Existing warning `HistoryJourney.swift:130` | Fixed |
| hidden-feature-gate, source | 6 hits, all the visible Touch ID / Face ID "Unlock" feature | Accepted: user-facing, documented |
| hidden-feature-gate, iOS archive | **0 hits** | PASS |
| hidden-feature-gate, Mac archive | 3 hits: local Ollama addresses (`localhost:11434`) | Accepted: reachable only from the visible Model menu and documented in the README; the Mac app is Developer ID, not App Store |

Not verified here: nutrition-label answers (Connected tools can contact services the person approves — the
privacy label needs your review), HealthKit capability on the App ID, and notarization.

## Archives (local)
- iOS (unsigned): `/Users/anupamchugh/Desktop/workspace/Pastport/build/archives/PastportiOS.xcarchive`
- macOS (Developer ID signed, hardened runtime, not notarized): `/Users/anupamchugh/Desktop/workspace/Pastport/build/archives/Pastport-macOS.xcarchive`

## What's new (draft)
Pastport is now on iPhone and iPad. See your timeline from photo activity and screenshots you add,
then ask questions in plain language. Answers use Apple Intelligence on your device and always show
the facts they come from. Private items stay behind Face ID or Touch ID, and nothing is read until you ask.

## Your upload steps (App Store Connect / Xcode are yours)
1. Enable HealthKit on the `com.anupamchugh.Pastport` App ID (the iOS entitlement needs it).
2. Open the iOS archive in Xcode Organizer → Distribute App → App Store Connect (Xcode signs with your Apple Distribution identity).
3. Add the screenshots, the what's-new text, and answer the privacy questions (Connected tools, Photos, Health, Location are all user-approved and on-device by default).
4. Mac: notarize and staple `Pastport.app` from the Mac archive with your usual flow, then `./release-preflight.sh`.
5. Submit for review yourself.
