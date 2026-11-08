# Pastport intelligence directions

Pastport helps someone return to things they have encountered. A visit is evidence that a page was opened, not evidence that it was read, bought, booked, or understood. The ideas below are proposals, not claims about the current app.

## What exists in this checkout

- On Mac, Safari history can be read after the person unlocks and grants access. The timeline, exact site questions, and source cards use the retained local snapshot.
- The history journey uses Foundation Models guided structures, focused tools, validation, and deterministic fallbacks. Agent Trail coordinates a small sequence in one session; it is not a fleet of independent agents.
- Vision classifies eligible local photos. An explicitly added screenshot goes through on-device OCR and redaction; screenshot narration is separately gated. No Visual Intelligence system integration is implemented.
- Alfred references are an opt-in, separate Batmobile source. The helper returns repository names, not clipboard history. Its full native walkthrough remains to be verified.
- No Pastport MCP server is present in this checkout, and none was exposed to the current Codex session. The separate Batmobile MCP exposes an Alfred repository search; that does not give Codex access to Pastport's Safari session.

## Ideas for the passport

1. **Return ticket:** collect a question's matching pages, dates, and safe links into a temporary trail. Let the person reopen a stop or export an explicitly reviewed note.
2. **Regular stops:** count distinct local calendar days per site in a selected window. Show the window and source visits; do not infer routines or personal traits.
3. **Research itinerary:** group related searches and later page visits as a tentative sequence, with actual timestamps and an explicit distinction between a search and a page.
4. **Then and now:** compare site counts between two equal windows, including coverage and missing data; never interpret a change as a mood or intent.
5. **Forgotten return:** surface older pages matching a person's current search, ranked deterministically with a reason, instead of claiming the person forgot them.
6. **Source passport:** show where each stop came from (Safari, user-added screenshot, or separately consented Alfred reference), plus its permissions and removal controls.
7. **Private bookmarks:** let a person explicitly save a small selection with a name and expiry. Define storage, encryption, deletion, and lock behavior before implementing.
8. **Visual recall:** on explicit image selection, use Vision OCR/classification or a multimodal Foundation Models prompt to describe the chosen image, then search only approved local evidence. The model's interpretation must be marked and source-linked; never silently attach private screenshots.
9. **Visual Intelligence search:** explore a system query returning only user-approved, non-sensitive saved items as app entities. Apple's integration shares entity representations with the system, so private history must remain excluded by default; verify supported devices, permissions, deletion and locked-state behavior before implementation.
10. **Codex companion:** provide a local MCP server with typed status, bounded search and evidence retrieval. No history read until the user opens a session in Pastport and approves the specific client and scope. Give tools limited sanitized results, no ambient disk access, network, raw screenshots, arbitrary command execution, or automatic export. Test lock, expiry, disconnect, concurrent clients, client identity, and redaction before enabling it.

## Guided shapes and roles to prototype

- `TrailPlan` contains bounded `TrailStep` values with a supported focus and source; deterministic code validates every step before execution.
- `EvidencePacket` contains scoped counts and safe references, while private URLs and raw image text stay outside the model prompt.
- `TrailStop` contains evidence references, a short interpretation, uncertainty, and a provenance label. A verifier checks that references resolve and numerical claims match; it cannot guarantee all semantic claims.
- `RevisitQuestion` suggests a follow-up only from supported evidence. A deterministic alternative is available when the model cannot run.
- A planner, source reader, and evidence reviewer can be separate logical stages. If independent agents are later implemented, give them separate sessions, bounded tool permissions, cancellation, and observable receipts; do not describe stages as independent agents today.

Foundation Models `@Generable` and `@Guide` constrain output shape, not factual correctness or permission. Tool execution remains app-controlled. See [guided generation](https://developer.apple.com/documentation/foundationmodels/generable), [multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting), and [Visual Intelligence integration](https://developer.apple.com/documentation/visualintelligence/integrating-your-app-with-visual-intelligence).
