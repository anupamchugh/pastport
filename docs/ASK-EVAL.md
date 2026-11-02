# Ask eval

`pastport ask-eval` runs the app's real Ask path (`HistoryJourney`) on a fixed, fictional history
(30 visits, dated relative to today) and scores each answer against a truth worked out in Swift:
correct or not, and invented claims (names or figures that appear nowhere in the history, the question
or the expected answer). It uses the on-device Apple model on this Mac and never reads Safari.
Fixture and scorer: `Sources/PastportEval` (linked by the CLI only, never by an app).

Before = main at the rehaul merge. After = this branch. Same fixture, same scorer.

| Question | Before | After |
|---|---|---|
| top-sites | FAIL (invented 2) | PASS (invented 0) |
| top-site | FAIL (invented 1) | PASS (invented 0) |
| yesterday | FAIL (invented 1) | PASS (invented 0) |
| today | FAIL (invented 1) | PASS (invented 0) |
| last-visit | PASS (invented 2) | PASS (invented 0) |
| searched-yes | PASS (invented 1) | PASS (invented 0) |
| searched-no | PASS (invented 1) | PASS (invented 0) |
| bookings-june | FAIL (invented 1) | PASS (invented 0) |
| places | PASS (invented 2) | PASS (invented 0) |
| absent-site | PASS (invented 1) | PASS (invented 0) |
| last-7-days | PASS (invented 2) | PASS (invented 0) |
| total | PASS (invented 2) | PASS (invented 0) |
| researching | FAIL (invented 1) | PASS (invented 1) |
| hotel-booked | PASS (invented 1) | PASS (invented 0) |
| top-last-week | FAIL (invented 1) | PASS (invented 0) |
| top-last-month | FAIL (invented 1) | PASS (invented 0) |
| **Total** | **8/16, invented 21** | **16/16, invented 1** |

What changed: simple factual questions (top sites, counts, last visit, did-I-visit, did-I-search,
booking pages, places) are answered in code from the visits, so they cannot invent a count, date or
site. "yesterday", "today", "last week" and month names are real time windows. Open-ended questions
("What was I researching?") still go to Foundation Models, with the same number and booking-claim checks.
Of the 16 questions, 14 are now answered in code and 2 reach the model, so "16/16" measures the
routing and the code answers more than it measures the model. The remaining "invented" name is a
label the model repeats from its evidence lines (for example "Source").

## iPhone Ask instructions on `fm serve` (2 Nov 2026)

`TimelineAnswerPolicy.instructions` checked on the Mac's on-device Apple model through `fm serve`
(`127.0.0.1:1976`, model `system`). `fm serve` cannot run Swift tools, so the tool results were
pasted into the prompt in the app's own line format: 3 photo events (61 photos), one added booking
screenshot (a Kyoto hotel). Six questions, 5 runs each. "Shown" means the answer passes a copy of
`HistoryJourneyValidation.allowsNarrative`, the check the app applies; the rest fall back to the
recorded facts.

| | Before | After |
|---|---|---|
| Model answers shown | 19/30 | 18/30 |
| Shown answers that claim a trip or stay, or say "You don't know" | 9 | 0 |
| "How many photos in the last 30 days?" gives 61 | 5/5 | 4/5 |

Before: "Your last trip was on Oct 10, 2026." (3 runs), "Yes, you stayed in Kyoto…" (1), and
"You don't know…" for "What did I do on Saturday?" (5). The check could not catch these: the numbers
are all in the evidence. After: a booking screenshot is described as a booking for a date, and
missing facts are "I don't know" plus what is missing. The total-count line did not measurably help.
