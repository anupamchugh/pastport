# Design

Describes what the code uses today. The last section is the prototype direction and is not implemented. Paths are relative to the repo root.

## Tokens

None found. There is no theme, colour, font or spacing file in `Sources/PastportUI`, `Sources/PastportiOS` or `Sources/PastportBar`; `Color(` hex literals: none found. Views use SwiftUI system styles and repeat a few literals. The only colour assets are two app icons (`Sources/PastportiOS/Assets.xcassets`, `Sources/PastportBar/Assets.xcassets`); no `AccentColor` set was found, so the accent is the system default tint.

## Colour (as used)

- Text: `.secondary` for nearly all supporting copy (for example `Home.swift:34,48,205`), `.tertiary` for chevrons (`Home.swift:209`).
- Accent: `.tint` for the Home glyph (`Home.swift:29`) and user bubble (`AskViews.swift:91`); `Color.accentColor.opacity(0.12)` for user messages in Connected tools (`ConnectedAssistantView.swift:100`).
- Category tints: `.pink` photo activity (`Home.swift:145`), `.teal` screenshots and search (`Home.swift:148`, `EvidenceCards.swift:92`), `.orange` movement, travel and flags (`EvidenceCards.swift:21,128,165`).
- Surfaces: `.quaternary.opacity(0.35)` card fill (`Home.swift:214`, `ExploreViews.swift:74,149`, `AskViews.swift:117`), `.quaternary.opacity(0.5)` search field (`Home.swift:281`), `.background` with a quaternary stroke (`EvidenceCards.swift:150`).
- Light and dark come from the system; no custom dark palette.

## Type

System text styles only, counted over `Sources`: caption 23, callout 17, footnote 16, caption2 12, title3 9, title2 8, headline 5, subheadline 3. Welcome title is `.largeTitle.bold()` (`Home.swift:31`), sentence `.title3` (`:33`). Monospaced is used for URLs and source strings (`EvidenceCards.swift:145,161`, `ExploreViews.swift:36`). One fixed size: `.system(size: 44, weight: .semibold)` for the welcome glyph (`Home.swift:28`). No custom fonts.

## Spacing, radius, size (repeated literals, not tokens)

Padding 16 for screen edges (`PastportApp.swift:63`), 10-12 inside cards (`Home.swift:213`, `ExploreViews.swift:73`), 4 vertical for rows. Corner radius 12 for cards (`Home.swift:214`), 10 for chips and bubbles (`ConnectedAssistantView.swift:99`, `EvidenceCards.swift:86`), 9 and 8 for small items (`EvidenceCards.swift:34,151`). Max text width 420 and 360 (`Home.swift:35,48`). Welcome minimum height 460 (`Home.swift:83`). Buttons use `.borderedProminent` and `.bordered` with `.controlSize(.large/.small)` (`Home.swift:44`, `AskViews.swift:36`). Explicit 44 pt targets are not set.

## Motion

- Custom animation: none found (`withAnimation`, `.animation(`, `.transition`, `repeatForever`: no matches in `Sources`). `ProgressView().controlSize(.small)` is the only moving element (`SharedControls.swift:28`, `Home.swift:40`).
- `accessibilityReduceMotion` is not read anywhere; today that is safe because nothing animates. Any streamed-text or transition added later must read it and show text all at once under Reduce Motion.
- Rule: nothing flashes, pulses or blinks (the owner has epilepsy). No streaming cursor.

## Dynamic Type rules

Use text styles; avoid `.system(size:)` (one exception above, a decorative glyph that is `accessibilityHidden`). Cards use `maxWidth: .infinity` and wrap. `ViewThatFits(in: .horizontal)` is used for the movement card (`EvidenceCards.swift:132`). Rows with a fixed `frame(width: 30)` icon column (`Home.swift:199`) and a fixed 88 pt label column (`ConnectedAssistantView.swift:202`) must be checked at accessibility sizes.

## Layout and iPhone Duo

Must: choose layout from `horizontalSizeClass` and container width; never `UIScreen.main`, `userInterfaceIdiom` or orientation.
Today:
- `UIScreen`, `userInterfaceIdiom`, `interfaceOrientation`, `UIDevice`: none found in `Sources` or `Tests`.
- `horizontalSizeClass` is used once, in `RootView` (`Sources/PastportiOS/PastportApp.swift:35,38`): regular width shows `TimelineScreen` (min 320, ideal 420, max 480) beside `AskScreen`; compact shows a two-tab `TabView` (`:44-53`).
- No `NavigationSplitView`, `GeometryReader` or `onGeometryChange`. The 320-480 pane and the unconditional two-pane regular case do not yet match the prototype's pane pairs (Add beside Privacy) or a trailing tab rail.
- The Info.plist lists portrait and landscape orientations (`project.yml`); this is a capability list, not layout logic.
- Mac: window min 480x560 (`PastportBar/App.swift:37`), menu-bar panel fixed 520x620 (`:45`), `BarView` min 420x560 (`BarView.swift:32`). Fixed sizes are acceptable on Mac only.

## Components inventory (`Sources/PastportUI`)

`WelcomeView` (Home.swift:5), `HomeView` (:65), `FindingCard` (:181), `FindingDetail` (:221), `HistorySearch` (:262), `EvidenceAskView` (AskViews.swift:6), `AskComposer` (:52), `AskTurnView` (:80), `ExperimentDocument` (:159), `ConnectedAssistantView` (ConnectedAssistantView.swift:6), `TravelRow` (EvidenceCards.swift:6), `ThreadCard` (:41), `MovementCard` (:119), `FlowChips` (:180), `SelectedEvidence` (ExploreViews.swift:5), `PhotoActivitySection` (:49), `ScreenshotsSection` (:84), `ScreenshotAdder` (:105), `WindowPicker` (SharedControls.swift:5), `SessionStatus` (:20), `AnswerSourceMenu` (:38). App shells: `RootView`, `TimelineScreen`, `AskScreen` (PastportiOS), `BarView` (PastportBar). Cards are re-implemented per view rather than via one card component.

## Next (prototype direction) - NOT IMPLEMENTED

Source: https://claude.ai/artifact/JDQDineuNfWjuBsHv1pZUd (web mock).
- World: editorial evidence cards on parchment; monospaced digits and source labels; nothing that looks like a surveillance dashboard.
- Light: bg #F3EFE6, card #FFFDF8, card2 #EBE6D9, line #D8D1BF, ink #1C2330, muted #5D6573, accent teal #0F6B6B on white text. Source label chip: text #7A5A12 on #F6EAD0, 10 px mono uppercase.
- Page tag colours in the mock only: Real #1F6F4A, New #8A4B00, Sample #4A4A8A.
- Type: display Newsreader 700 (title 30, section 18), body Instrument Sans, mono JetBrains Mono 10-12. In the app these map to system serif/New York for titles, SF for body and SF Mono for source labels; a custom font is not required.
- Shapes: cards radius 20, buttons radius 12, chips fully round; card padding 14; tab bar with icon above 11 px label.
- Layout: compact has four tabs (Timeline, Ask, Add, Privacy) after an unlock gate with window chips (7 days, 30 days, 90 days, 1 year); Duo unfolded has two panes (Timeline plus Ask; Add plus Privacy) with a 62 pt tab rail on the trailing edge. Folded Duo is the compact layout.
- Patterns: locked screen first; evidence card = source chip, one human sentence, closed "How do we know this?" disclosure; redaction shown as dark bars; Face ID error, offline and "Apple Intelligence is off" banners with a coloured left border.
- Motion: only a 0.12 s button press scale in the mock, disabled under Reduce Motion; nothing pulses.
