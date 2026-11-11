# Opt-in visual recall — design (2026-11-11)

Status: design only. Nothing here is built, and it does not change the current product. It answers bead `pastport-2k9` with a recommendation and the checks a device must pass before any of it ships.

"Visual recall" means two different things that must not be blended:

| | A. Selected-image understanding | B. System Visual Intelligence search |
| --- | --- | --- |
| Who starts it | The person picks one image inside Pastport | The person points the camera or screenshots, in the system UI |
| Where the image goes | To the on-device model in Pastport's own session | To an App Intents query Pastport implements (`IntentValueQuery`, `SemanticContentDescriptor`) |
| What Pastport returns | A reading shown in the app, marked as the model's | `AppEntity` values the system shows and keeps in its own search UI |
| Privacy exposure | None beyond the app | Entities are shared with the system; private history would leave the app's lock boundary |
| Recommendation | Build, behind consent | Do not build for history or screenshots |

## A. Selected-image understanding (recommended)

Use the Foundation Models multimodal prompt (`Attachment(image)` in a `LanguageModelSession` prompt) on one image the person chose with the existing picker. Apple's guidance is to try the on-device model first; fall back to `PrivateCloudComputeLanguageModel` only as an explicit, separately consented step, and treat it like the off-device Connected tools tier (named in the approval, never given history).

Rules, taken from what the app already enforces:

1. **Explicit selection only.** One image per request, from the picker. No library scan, no background read, and the image is not kept: it exists in memory for the call, as screenshots do today.
2. **Text first, by Swift.** Run the existing Vision OCR and scrubber. Emails, one-time codes and card numbers are replaced before anything reaches the model. If the model sees pixels, those pixels can still show a code, so a multimodal prompt is allowed only for an image the person has just viewed in full, with a notice that the model sees the image. Chat, banking, receipt and unclassified screenshots stay behind the existing narration opt-in (`ScreenshotKind.requiresNarrationOptIn`).
3. **The model's reading is labelled.** The card says "Model's reading of the image you chose" and keeps the OCR text it is based on. It is an interpretation, never a fact in the evidence packet, and it cannot create a booking, a place or a count.
4. **Search stays on approved evidence.** A description may suggest words to search for, but the search runs only over the already unlocked, in-memory evidence, by Swift. The model does not receive history.
5. **Lifecycle.** Lock, background, cancel, a new selection and Clear drop the image, the reading and any pending request. A reading that finishes after a lock is discarded.
6. **Guided output.** Use `@Generable` with a small closed label set and a short free-text description with a length limit, so the result is bounded.

Acceptance checks for A (device with Apple Intelligence; the simulator cannot run the model):

- Pick a fictional image; the card shows the reading marked as the model's and the scrubbed OCR text beside it.
- Cancel the picker: nothing is read. Lock while the model is running: no reading appears afterwards.
- Remove the screenshot: its reading and text are gone from Ask evidence.
- With Airplane Mode on, the flow still works (on-device path).
- A fictional screenshot containing a code and an email shows neither in the card or in Ask.

## B. System Visual Intelligence (not recommended for history or screenshots)

Visual Intelligence calls an `IntentValueQuery` that returns `AppEntity` values; the system displays and may index them, and tapping one opens the app. Apple's integration shares those entity representations with the system, so anything returned is outside Pastport's lock.

Pastport removed its earlier `AppEntity` types on 2 Nov 2026 (commit `bd524a8`: unused queries returned nothing, and the Siri path bypassed the lock), and the 2.0 iPhone spec allows at most one data-free `OpenTimelineIntent`. Returning history, photo clusters or screenshots would reverse both.

If the owner still wants a system search surface, the only safe shape is the "private bookmarks" idea in `docs/intelligence-directions.md` (idea 7): items the person explicitly saves, with a name and an expiry, stored encrypted, never derived from history, screenshots or Photos, and returned by the query as an empty list while Pastport is locked. That needs its own spec before code: storage, deletion, what the system retains after deletion, behaviour on unsupported devices and the iOS 27 entity indexing rules.

Acceptance checks for B, if ever built: denial (Visual Intelligence permission off) returns nothing; locked returns nothing; deleting a saved item removes it from system results within a refresh; a history page or screenshot never appears.

## Not verified

No Apple Intelligence device or Visual Intelligence camera was available, and nothing was run. The API behaviour above is from Apple's documentation ("Analyzing images with multimodal prompting", "Integrating your app with visual intelligence"). The owner decides whether A is worth building and whether B stays out.
