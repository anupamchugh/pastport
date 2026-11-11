# Safari history import for iPhone and iPad — design proposal (2026-11-04)

Status: implemented in code on 11 Nov 2026 (`ZipArchive`, `SafariExport`, `ImportedHistorySource`, `SafariImportSection`); the
real-export and iPhone checks in the acceptance list are owner steps still to run. This document does not authorize a release. It resolves the privacy and data-shape questions that kept Safari snapshot import out of
the 2.0 specification.

## Product shape

Pastport cannot read Safari's private history database directly on iPhone or iPad. The supported
user-mediated route is Safari's own export: the person exports a ZIP from Safari Settings and then
chooses that ZIP in Pastport. `SFSafariSettings.openExportBrowsingDataSettings()` may open the
system export sheet while Pastport is foregrounded, but the app must still receive the resulting
file through a document picker.

The first version should import a local, scrubbed snapshot for one session. It should not sync
between devices, upload the archive, or retain the original ZIP.

## Input and parser contract

1. Present `fileImporter`/`UIDocumentPickerViewController` for ZIP files only. Do not accept a
   directory, a password export, a CSV, or arbitrary JSON as a Safari snapshot.
2. Read the selected security-scoped URL while access is active, with a documented archive-size
   limit (suggested: 50 MiB); release access as soon as parsing ends. Do not copy the archive.
3. Inspect ZIP entries without extracting files to disk. Reject symlinks, path traversal (`..`),
   duplicate paths, and archives that exceed an uncompressed-size limit (suggested: 200 MiB)
   or entry-count limit (suggested: 10,000 files).
4. Find localized `History*.json` files and validate the top-level `metadata` object before
   reading rows: `browser_name` must be Safari or Safari Technology Preview and `data_type` must
   be `history`. Ignore `Passwords*.csv`, `PaymentCards*.json`, `Extensions*.json`, bookmarks,
   and unknown files. Never log their names or contents.
5. Decode only `url`, optional `title`, `time_usec`, and optional `visits_count`. Ignore redirect
   URLs and all unknown keys. Require an absolute `http` or `https` URL and a valid timestamp.
6. Apply hard row and text limits before constructing `Visit` values (suggested: 100,000 rows,
   8 KiB title, 8 KiB URL). Deduplicate by the existing canonical URL and sort newest first.
7. Remove query strings and fragments before the snapshot becomes visible to UI or models. Keep
   the original URL only transiently while parsing and never persist it.

## Lifecycle and privacy

- Require Face ID/passcode immediately before import and again before the first Ask operation if
  the app has been backgrounded. The import is local and read-only.
- Store only the scrubbed `Visit` snapshot in memory. Do not write the ZIP, raw JSON, raw URLs,
  titles, or model transcript to disk, iCloud, logs, analytics, clipboard, or connected tools.
- Clear the imported snapshot on lock, scene background, explicit Clear, failed authentication,
  and app termination. Display the source as `Safari export · imported on this device`, with its
  date range and row count.
- Imported history is not silently merged with Photos activity. The iOS source model should gain
  an explicit imported-history source and a coverage marker; the existing "iOS does not let apps
  read Safari history" copy must become "Safari history is available only from an export you chose"
  while an import is present.
- Ask may use the same deterministic facts and Foundation Models tools as Mac history, but all
  off-device Connected tools continue to receive no history.

## Failure behavior

Every failure is fail-closed and leaves the previous timeline untouched: user cancelled, archive
too large, unsafe ZIP, no valid history file, unsupported metadata, malformed rows, too many rows,
or authentication failure. The UI explains the next action without naming sensitive files. A
partial parse is never presented as complete; if the row cap is reached, coverage says `partial`
and Ask must not claim lifetime totals.

## Acceptance checks

- Fixture ZIPs cover one profile, multiple profiles, localized names, redirects, malformed rows,
  zip-slip entries, symlinks, duplicate paths, oversized archives, and password/payment files.
- Unit tests prove the parser never emits query strings/fragments, never reads password or payment
  contents, enforces all limits, and reports partial coverage.
- UI tests prove picker cancellation, authentication cancellation, background/lock clearing, and
  that an imported snapshot is visually distinct from live Mac history.
- A device test proves Safari export is user-mediated and no network request occurs during import
  or Ask. Release work remains gated on the owner’s signing and distribution approval.

## References

- Apple, [Importing data exported from Safari](https://developer.apple.com/documentation/safariservices/importing-data-exported-from-safari)
- Apple, [`SFSafariSettings.openExportBrowsingDataSettings`](https://developer.apple.com/documentation/SafariServices/SFSafariSettings/openExportBrowsingDataSettings(completionHandler:))
- Current product boundary: `docs/specs/2026-10-21-pastport-2.0-iphone.md`, section 8.
