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
swift build -c release
./install.sh
```

Grant Full Disk Access to the app or terminal when prompted. The safe demo mode never reads Safari history:

```bash
./install.sh --demo
```

## CLI

```bash
pastport recent
pastport bookings
pastport trail
pastport trackers
pastport ask "what did I book and where did I stay"
pastport eval --runs 3
```

`recent`, `search`, `top`, `when`, `stats`, `bookings`, and `trackers` run without a model. `brief`, `trail`, `threads`, `ask`, `agent`, and `eval` can use Apple Foundation Models or local Ollama.

## Development

```bash
swift test
```

Detectors use synthetic visits and wire-format shape, not brand-name lists. Contributions should preserve that rule.

MIT licensed.
