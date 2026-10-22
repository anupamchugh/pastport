# Pastport 1.3.0 (10) — customer rehaul, release-ready (not uploaded)

Local only. Nothing was uploaded, signed in, or sent to App Store Connect or any remote except this branch.
Branch `claude/pastport-customer-rehaul` (on top of `main` 25e0900, which already has the rehaul + release prep).

## What changed for customers
- **Home leads with the general job:** search your history in plain words ("Find a page you have seen before"),
  then *What you've been into* (research topics, this week's top sites), *Privacy check* (trackers, links that carry a
  location), and *Trips and bookings* last, as one card among them. First-run sentence and README lead the same way.
- **One switcher** (Home / Ask) on Mac and iPhone; Connected tools is an "Answer from" menu; Lock, window, model and
  export live in one More menu. No internal nouns ("retained", "Foundation Lab", "Demo data") in the main UI.
- **Ask opens with 3–4 tappable starter questions** the data can answer; evidence lines sit under "Based on".
- Plain plurals ("1 photo", "2 booking pages"); one-line iPhone explainer; screenshots shown as readable summaries.
- Privacy and grounding unchanged: a sensitive topic is neither named nor counted on a card; the number check and
  booking-claim guard still apply; Touch ID/Face ID, lock and clear, nothing read until you choose.

## Ask accuracy (on-device Foundation Models, this Mac)
`pastport ask-eval`: fictional 30-visit history, 16 simple questions, truths computed in Swift.
**Before 8/16 correct, 21 invented claims. After 16/16, 1 invented claim.** Full table: `docs/ASK-EVAL.md`.
Honest caveat: 14 of the 16 questions are now answered in code (no model), so the score measures routing and the
code answers more than the model; open-ended questions still go to Foundation Models.
Cause of the failures: "yesterday/today/last week/June" were rejected as unsupported date phrases, everyday words
became search keywords, ties in top sites had no stable order, and bare "… - Search" titles formed no research thread.

## Tests and builds (iOS 27.1 / macOS 27.0 SDKs, Xcode 27.1)
- `swift test`: **98 XCTest + 88 Swift Testing executed, 0 failures.**
- Mac and iOS Release archives succeeded, no code warnings.
- Hidden-feature gate: iOS archive **0 hits**; source 6 hits (all the visible Touch ID "Unlock"); Mac archive 3 hits
  (visible, documented local Ollama addresses; Mac is Developer ID, not App Store).
- Fixture/scorer live in `PastportEval`, linked only by the CLI, never by an app.

## Screenshots
`docs/screenshots/before/` and `after/`: Mac light and dark (welcome, home, search, Ask empty, Ask answered) and
iPhone 17 Pro light and dark (iOS 27.0 simulator; welcome, home, Ask empty, Ask answered). Before shots are the build at
the rehaul merge. `docs/screenshots/fallback-apple-intelligence-not-ready-ios.png` shows Ask with Apple Intelligence not ready.
The simulators were deleted.

## Installed
`/Applications/Pastport.app` was the 1.3.0 (10) build of 18 Oct 14:45, from before the rehaul (no app icon).
It is now this branch's Developer-ID-signed build (not notarized). The old app is kept at
`/Users/anupamchugh/Desktop/workspace/Pastport/build/backup/Pastport-1.3.0-pre-rehaul.app`.

## Archives (local)
- iOS (unsigned): `/Users/anupamchugh/Desktop/workspace/Pastport/build/archives-customer-rehaul/PastportiOS.xcarchive`
- macOS (Developer ID signed, hardened runtime): `/Users/anupamchugh/Desktop/workspace/Pastport/build/archives-customer-rehaul/Pastport-macOS.xcarchive`

## What's new (draft)
Pastport helps you find a page you have seen before. Search your Safari history in plain words on your Mac, see what
you have been into, check for trackers and links that carry a location, and review trips. Now on iPhone and iPad too:
build a private timeline from your photos and screenshots, then ask it questions. Answers use Apple Intelligence on your
device and show what they are based on. Nothing is read until you ask, and everything stays on your device.

## What's new, Pastport 2.0 for iPhone and iPad (draft)
Pastport now builds a private timeline on iPhone and iPad from your photo activity and the screenshots you add, in four
tabs: Timeline, Ask, Add and Privacy. On iPhone Duo and iPad the screen opens into two panes. Open Timeline is a
Shortcuts action (also by voice or Spotlight: "Open my timeline in Pastport") that opens Pastport on the locked
screen. Connected tools (Ask, "Answer from") can use Health, Weather, Contacts, Calendar, Reminders, Location and Music
once you turn a tool on and allow each request.

## Notes for Review (2.0, draft)
- **Open Timeline** (`OpenTimelineIntent`, the app's only App Intent) is listed in Shortcuts and works by Siri phrase
  "Open my timeline in Pastport". It only opens the app on the locked Timeline; it reads nothing and returns no data.
  Face ID or passcode is still asked before photo activity is read.
- **Health** is under Ask → Answer from → Connected tools → Health. It is read-only (`toShare: []`) and reads: steps,
  heart rate, workouts, sleep, active energy and distance. A tool is off until the person turns it on, and every
  request shows its exact arguments and needs Allow once. Health data is never stored and is cleared on lock and when
  the app leaves the foreground. Nothing is sent off the device by Health; Weather and web tools are labelled
  "Sends data off this iPhone".
- Place names and photos stay on the device; photo coordinates are not read.
- No demo or test switches ship in the Release build (hidden-feature gate: binary 0 hits).

## Your upload steps
1. Enable HealthKit on the `com.anupamchugh.Pastport` App ID.
2. Open the iOS archive in Xcode Organizer → Distribute App → App Store Connect.
3. Add screenshots from `docs/screenshots/after/`, the what's-new text, and answer the privacy questions.
4. Mac: notarize and staple the Mac archive's `Pastport.app`, then `./release-preflight.sh`.
5. Submit for review yourself.
