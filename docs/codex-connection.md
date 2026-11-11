# Codex connection (Mac)

Pastport can answer a local coding agent such as Codex about the Safari history you already unlocked. It is off every time Pastport starts, and nothing is shared until you allow a specific kind of access.

## Set up

1. Build or install the Mac app and the CLI (`swift build -c release --product pastport`).
2. Add the server to Codex: command `pastport`, argument `mcp` (for example in `~/.codex/config.toml`, a `[mcp_servers.pastport]` table with `command = "<path to pastport>"` and `args = ["mcp"]`).
3. In Pastport, unlock and read your history, open **Codex** in the sidebar and switch on **Allow Codex to connect**.
4. Ask Codex to use the Pastport tools. A prompt appears in the Codex view naming the client; choose **Allow for 15 minutes**, **Allow for 1 hour** or **Decline**.

`pastport mcp` reads no history. It only copies lines between Codex and the app's socket. If the app is not running, locked or switched off, every tool answers with a plain refusal.

## What a client can do

| Tool | Needs approval | Returns |
| --- | --- | --- |
| `pastport_status` | no | whether Pastport is unlocked and what this connection may do |
| `pastport_search` | `history.search` | up to 10 pages: scrubbed title, site, short path, day |
| `pastport_top_sites` | `history.top_sites` | up to 10 sites with visit counts |

There is no tool for files, network, commands, screenshots, photos, Alfred, writing or export. Topics Pastport hides until you ask (`SensitiveTopics`) are left out of both tools.

## Threat model

Safari history, page titles and screenshots are untrusted content: a page title can contain instructions. The design therefore keeps the model out of the permission decision.

- **Consent is made by the person, per client and per scope.** The prompt shows the name the client claims and, from the kernel, the program that is actually connecting and the program that started it. A second connection is asked again; it cannot reuse another's approval.
- **Approvals end** on expiry (capped at 1 hour), on lock, when the switch is turned off, when the client disconnects or cancels, and a denial is not retried for 5 minutes.
- **Results are bounded and cleaned.** No query strings, fragments, addresses, card numbers, times of day or opaque path segments; at most 10 rows; 20 calls a minute per connection.
- **The socket is private.** A Unix socket in a 0700 folder with mode 0600; connections from another user are closed; at most 4 clients.
- **Tool descriptions and results are static text** written by Pastport; no page content is placed in a tool description.
- **Imported iPhone exports are never offered.** Only Mac Safari history in the unlocked session is visible.

## Not verified

The real Codex walkthrough (adding the server to Codex, seeing the prompt, approving and calling a tool, then locking) needs the owner's Mac with the screen unlocked and Codex installed. See bead `pastport-7t3`.
