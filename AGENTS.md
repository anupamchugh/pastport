# Repository Guidelines (Pastport)

Pastport searches your own Safari history in plain words, privately, as a macOS menu-bar app, an iPhone and iPad app and a CLI. `README.md` describes the features and the privacy boundary.

This repository is public (`github.com/anupamchugh/pastport`). Anything pushed is published: no private paths, tokens or personal data in code, docs or commits.

## Structure
- `Package.swift` owns all code: `PastportKit` (cross-platform core; links only FoundationModelsKit, so another app such as Feedloom can depend on it alone), `PastportConnected` (opt-in Connected tools; the only target that links FoundationModelsTools; the apps reach it through `model.connectedAssistant`), `PastportUI` (shared SwiftUI; no AppKit, UIKit or I/O), `PastportMac` (Safari reader on a copied database via `/usr/bin/sqlite3`, osascript, Ollama), `PastportEval` (fictional Ask fixture and scorer, linked by the CLI only, never by an app), executables `pastport` (CLI) and `PastportBar`.
- `project.yml` (XcodeGen) wraps the package into two apps that share bundle `com.anupamchugh.Pastport`: `Pastport` (macOS menu-bar, `Sources/PastportBar`) and `PastportiOS` (iPhone and iPad, `Sources/PastportiOS`).
- Read before changing behavior: `PRODUCT.md`, `DESIGN.md`, `docs/specs/`, `docs/ASK-EVAL.md`.

## Build/Test
- Main gate, no simulator: `swift test` in the root. Passing means both summaries report 0 failures: XCTest `Executed N tests, with 0 failures` and Swift Testing `Test run with N tests ... passed`. Quote both counts. Narrow with `swift test --filter <Suite>`.
- `Pastport.xcodeproj` is generated and gitignored. Run `xcodegen generate` before any `xcodebuild` and after adding, moving or deleting a source file. Edit `project.yml`, never the project.
- Mac app: `xcodebuild -project Pastport.xcodeproj -scheme Pastport -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode build`. Passing: `** BUILD SUCCEEDED **`.
- iOS app: `xcodebuild -project Pastport.xcodeproj -scheme PastportiOS -destination 'generic/platform=iOS Simulator' build` (unverified destination).
- Schemes (`xcodebuild -list`): apps `Pastport`, `PastportiOS`; package schemes `pastport`, `PastportBar`, `PastportKit`, `PastportConnected`, `PastportMac`, `PastportUI`, `PastportEvalTests`. No `.xctestplan` files; the app targets have no test bundles, so every test is a package test.
- Scripts: `bash -n install.sh release-preflight.sh package-release.sh` (CI runs it). Lint: `swiftlint` (`.swiftlint.yml`; CI does not run it).
- Ask eval: `swift run pastport ask-eval` (unverified invocation) runs on-device Foundation Models against the fictional fixture; needs Apple Intelligence on this Mac. Results go in `docs/ASK-EVAL.md`.

## Coding Style
- Swift tools 6.2. `PastportKit` builds in Swift 6 language mode (target `swiftSettings`, 0 warnings); the other targets and `project.yml` stay on Swift 5 (`swiftLanguageModes: [.v5]`, `SWIFT_VERSION 5.0`). Move one target at a time: measure with `swift build -Xswiftc -strict-concurrency=complete` (use a separate `--scratch-path`), fix to 0 warnings first, then flip. Keep framework `Response` values inside the isolation that made them; no `@unchecked Sendable` wrappers.
- Swift computes the facts; the model only phrases a small evidence packet. If the evidence has no answer, say so. Number and booking-claim checks must stay.
- Detectors work from synthetic visits and wire-format shape, never brand-name lists.
- Safari history is copied to a temp location and read-only; query strings are stripped by default; the history conversation has no network tools; Connected tools never receive Safari history.

## Testing
- Add tests in `Tests/PastportKitTests` (or `PastportMacTests`, `PastportEvalTests`) for detector, answer and parsing changes. XCTest and Swift Testing are both used; follow the file you touch.
- Fixtures are fictional (`DemoData`, `PastportEval`). Never commit real history, real screenshots or personal data.
- Real Safari, Photos, Siri, Health and Apple Intelligence flows need the owner's Mac or iPhone. Say which steps ran and which did not.

## Tasks (Beads)
- Ledger: `.beads/` in the main checkout (prefix `pastport`), not in Git. `bd` from a worktree resolves to it; check with `bd --readonly where`.
- Loop: `bd ready` → `bd update <id> --claim --actor <amp|claude|codex>` (never take another agent's live claim) → `git worktree add .claude/worktrees/<slug> -b bd-<id>-<slug> origin/main` in the main checkout (find it with `git worktree list`; `git fetch` first) and work there → commit with the bead id in the message → `bd comments add <id> "<commit, test counts, what ran where>"` → `bd close <id> --reason "<outcome>"`. Owner gates get a comment, not a close.

## Commit & PR
- Subjects state the user-visible outcome in plain words, ending in the bead id, e.g. `... (pastport-26g)` (see `git log --oneline`).

## Releases
- Versions: the `Pastport` target overrides to `MARKETING_VERSION 1.4.0` / `CURRENT_PROJECT_VERSION 11`; `PastportiOS` uses the base `1.3.0` / `10`. A new build number must exceed any uploaded one.
- Mac ships as a Developer ID DMG/ZIP on GitHub Releases, not the App Store. Bead `pastport-tn6` puts the 1.4 candidate on branch `codex/pastport-research-brief` (a local branch, not on origin; 3 commits ahead of `main` on 10 Nov 2026), so package Mac releases from that branch. Agents may run `./package-release.sh --unsigned-preview` (writes `.build/releases/<version>/`). Signing with `--sign`, notarizing (`--asc` or `--notary-profile`), `./release-preflight.sh` on the signed app and the GitHub release need owner approval (below). Notes: `docs/release-notes-<version>.md`.
- iOS ships through Xcode Organizer to App Store Connect. `RELEASE-READY.md` is a 1.3.0 (10) snapshot, not current. The iOS version to ship, the last uploaded build and the archive command are unknown, so ask the owner before archiving.
- Hidden-feature gate: `/usr/bin/python3 ~/.agents/skills/hidden-feature-gate/scripts/gate.py --source Sources/PastportKit --source Sources/PastportUI --source Sources/PastportMac --source Sources/PastportBar --source Sources/PastportiOS`, then `--binary <PastportiOS.xcarchive>` (iOS) or `--binary .build/release-build/Build/Products/Release/Pastport.app` (Mac, after `package-release.sh`). Exit 0 is a pass.
- Upload, submit, signing, notarizing, publishing a release and metadata publishing run only after the owner approves that exact action (version, build, destination) in the current conversation. Without that, stop after the archive and report the archive path, gate results and the exact command. This also covers signing identities, App ID capabilities, screenshot publishing and GitHub releases. Push stays with the owner.

## Agent Notes
- `RELEASE-READY.md` names local archive paths under a home folder; do not copy that style into new docs.
- CI (`.github/workflows/ci.yml`) runs `swift test` on the `xcode-27` runner label (Xcode 27.1). The `macos-26` image stops at Xcode 26.6, which cannot build the 27 package (`PhotosPickerItem` not found). It skips `testProductionReaderUsesVisionBeforeScrubbing` because Vision cannot run on GitHub-hosted runners (`unknownError`); that test runs locally. Do not lower the iOS 27 / macOS 27 floor to make CI green.
- `swift test` needs the Mac screen unlocked. `ScreenshotReader.read(imageData:)` writes its temporary file with `.completeFileProtection`, which fails while the screen is locked, so 6 screenshot tests in `TimelineModelTests` time out with "That image could not be read." (checked 11 Nov 2026: `CGSSessionScreenIsLocked` true, the same write fails in a bare Swift script). This is the environment, not a regression; rerun after unlocking. Check with `/usr/bin/python3 -c "import Quartz;print(Quartz.CGSessionCopyCurrentDictionary().get('CGSSessionScreenIsLocked'))"`.
- Under heavy machine load a timing assertion can fail; `boundedTaskDoesNotWaitForNonCooperativeWork` now allows 1 s for that reason.
- Demo mode (fictional data, `--demo`, and the other `--*-demo` launch flags) exists only in Debug builds. Release builds must not contain it. The one sample path in Release is the visible "Try with sample history" button (`SampleHistory`, fictional `.example` pages, iPhone/iPad only): it must stay a visible control, never a flag.
- The Mac app must not be App-Sandboxed (the sandbox blocks Safari's `History.db`). Local builds sign ad hoc (`CODE_SIGN_IDENTITY "-"`).
- `./install.sh` replaces `/Applications/Pastport.app` and launches it. Run it only when the owner asks, with Pastport quit.
- `package-release.sh` refuses to overwrite artifacts and fails if `/Users/` appears in the bundle or `get-task-allow` is set. Fix the cause; do not weaken the check.
