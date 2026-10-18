# Pastport

**Your browser history knows where you live. Pastport helps you read it.**

Pastport is a native macOS app and CLI for finding travel trails, bookings, threads, and trackers in your own Safari history. It runs locally, behind Touch ID, with no cloud account or hosted database. It can use Apple Foundation Models on macOS 26 or a local Ollama model; neither path sends data to a cloud service.

![Pastport Recent view](docs/pastport-recent.png)

## The boundary

Swift computes the facts. The on-device model only phrases a small evidence packet. If the evidence does not contain an answer, Pastport should say it does not know.

The live history database is copied to a temporary location and queried read-only. Query strings are stripped by default, sensitive threads are gated, and nothing leaves the Mac.

## What it finds

- **Movements** — coordinates and timestamps carried by links.
- **Bookings** — confirmations, itineraries, receipts, and booking activity.
- **Threads** — short bursts of related activity.
- **Trackers** — redirects, interstitials, and attribution parameters.

## Install

Requires macOS 14 or later. Apple Foundation Models require macOS 26 with Apple Intelligence enabled. Download the signed, notarized app from the [latest release](https://github.com/anupamchugh/pastport/releases/latest), or build it yourself:

```bash
git clone https://github.com/anupamchugh/pastport
cd pastport
brew install xcodegen
./install.sh
```

The app starts with history and Photos closed. Choose **Read history**, then grant Full Disk Access to the app in System Settings if needed. Photos are optional: **Photo activity → Read photo activity** authenticates first and asks for Photos access only when you choose. It reads up to 500 local images, classifies ordinary photos on-device, and counts screenshots without inspecting their pixels. No iCloud image downloads are requested.

**Lock & clear** clears cached history, photo activity and answers in both the window and menu-bar panel. Screen lock does the same. Changing the date range clears old evidence before another read.

The source installer creates an ad-hoc-signed local development build, not a notarized distribution. The safe demo mode never reads Safari history:

```bash
./install.sh --demo
```

## CLI

```bash
pastport recent
pastport bookings
pastport trail
pastport trackers
pastport photos --days 30
pastport ask "what did I book and where did I stay"
pastport eval --runs 3
```

`recent`, `search`, `top`, `when`, `stats`, `bookings`, and `trackers` run without a model. `brief`, `trail`, `threads`, `ask`, `agent`, and `eval` can use Apple Foundation Models or local Ollama.

## Build a DMG

Use Xcode and XcodeGen. To produce an explicitly labelled local preview without distribution credentials:

```bash
./package-release.sh --unsigned-preview
```

For a public distribution, supply your Developer ID identity and either existing `asc` authentication or a notarytool keychain profile:

```bash
./package-release.sh --sign 'Developer ID Application: Your Name (TEAMID)' --asc
# Or use an existing notarytool keychain profile:
./package-release.sh --sign 'Developer ID Application: Your Name (TEAMID)' --notary-profile YOUR_PROFILE
```

The script builds the native app, checks its version, creates DMG and ZIP artifacts and a SHA-256 manifest. The signed path notarizes and staples both the app and DMG and runs Gatekeeper verification. It never installs the app or publishes to GitHub. Unsigned previews are not suitable for public distribution.

## Development

```bash
swift test
```

Detectors use synthetic visits and wire-format shape, not brand-name lists. Contributions should preserve that rule.

MIT licensed.
