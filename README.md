# Apple Notes Link Preview

A standalone macOS Swift CLI script that scans links in the currently open Apple Notes note and batch-converts them into rich link preview cards using Apple Notes' native **Show Link Preview** context menu action.

Current version: **V11**

## Features

- **Safe dry-run scanning**: Inspects all candidate links in the active note without modifying anything.
- **Native UI automation**: Uses macOS Accessibility API (`AXUIElement`) and native HID mouse events (`CGEvent`) with automatic right-click / Control-click retries and scroll-into-view fallback.
- **Inline link protection**: Selects and verifies the complete link range before triggering menus on inline links.
- **Mixed-script link normalization (V11)**: Works around an Apple Notes bug where mixed-script link titles (e.g., mixed English + CJK such as `Python 官方文档`, `统计计算 R 语言`, or `GitHub 开源平台`) only partially convert and leave trailing text fragments behind. Before triggering **Show Link Preview**, V11 temporarily normalizes mixed-script titles to their verified pure-ASCII URL via Notes' **Edit Link** dialog, verifies exact occurrence-level text and URL invariants, and automatically restores the original title if preview conversion cannot proceed.
- **Strict guardrails**: Continuously verifies Apple Notes focus, rescans after each conversion, checks ordered link identities, and halts immediately with diagnostics on any unexpected change.
- **Multilingual Notes UI support**: Matches Apple Notes context menus and dialogs in English, Simplified Chinese, and Traditional Chinese.

## Requirements

- macOS with Apple Notes
- Xcode Command Line Tools (`swift`)
- **Accessibility permission** granted to the terminal app running Swift:
  - Open **System Settings → Privacy & Security → Accessibility** and enable your terminal app (e.g., Terminal, iTerm2, Warp, VS Code).

## Usage

Always test on a **disposable or duplicated note** first. Keep Apple Notes active in the foreground and click inside the note body within 5 seconds of running the command.

### Direct Execution

```zsh
# Dry run (read-only scan; highlights mixed-script links that V11 will normalize)
swift ./notes-link-preview.swift

# Convert candidate links (V11 mixed-script normalization enabled by default)
swift ./notes-link-preview.swift --apply

# Convert without mixed-script normalization (V10 behavior)
swift ./notes-link-preview.swift --apply --no-normalize-mixed
```

Running `swift` directly prints full `DEBUG:` diagnostics and preserves the process exit code.

### Optional Shell Aliases (`~/.zshrc`)

```zsh
alias nls='swift "$HOME/Projects/apple-notes-link-preview/notes-link-preview.swift" | grep -v "^DEBUG:"'
alias nlp='swift "$HOME/Projects/apple-notes-link-preview/notes-link-preview.swift" --apply | grep -v "^DEBUG:"'
```

| Command | Behavior |
| --- | --- |
| `nls` | Read-only scan listing candidate links (including duplicate URLs by occurrence) and flagging `[mixed-script: "..."]` entries. |
| `nlp` | Rescans and converts candidate links in the active note from bottom to top. |

## Safety Notes

- On verification failure or focus loss, the script stops immediately with a non-zero exit code.
- Previously converted links in the same batch remain in the note; inspect remaining links and surrounding text before deciding whether to undo.
- If **Show Link Preview** cannot be triggered after normalizing a mixed-script link and the note text has not partially mutated, V11 automatically restores the original link title via **Edit Link**.

## Repository Structure

- [notes-link-preview.swift](notes-link-preview.swift) — Main single-file Swift script (V11).
- `backups/` — Byte-for-byte snapshots of V1 through V11 (`v1`–`v11` are also preserved as Git tags).
- [CHANGELOG.md](CHANGELOG.md) — Version-by-version history (V1–V11).
- [DEVELOPMENT.md](DEVELOPMENT.md) — Implementation details, attempted approaches, and diagnostics notes.
- [TESTING.md](TESTING.md) — Historical test observations and regression checklist.
- [ROADMAP.md](ROADMAP.md) — V11 link normalization design and verification criteria.
- [AGENTS.md](AGENTS.md) — Development handoff notes.
