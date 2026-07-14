# Hacker News Draft - QDock

## Suggested title

`Show HN: QDock - open-source macOS menu bar app for Claude + Codex quota tracking`

## Post body

I built **QDock**, a native macOS menu bar app that shows Claude Code and Codex usage/quota in real time.

I initially built it for myself because I kept hitting rate limits unexpectedly during coding sessions.
Then I open-sourced it and added a few security-focused constraints:

- Manual tokens are stored in macOS Keychain (not in app prefs/files).
- Claude detection is file/CLI based; it does not touch Keychain during detection.
- For Claude usage, QDock calls the usage endpoint only.
- For Codex, QDock talks to `codex app-server` over local stdio JSON-RPC.
- Installer verifies SHA-256 checksums and aborts if verification data is missing.
- Auto-update pins installer package version and validates version format before running `npx`.

I am trying to keep this tool useful but also transparent about trust boundaries.
**Current limitation:** releases are currently unsigned and not notarized (working on improving this release trust model).

If you try it, I would especially love feedback on:

1. security model / trust assumptions
2. provider support priorities
3. where onboarding still feels fragile

Repo: https://github.com/altansaid/QDock

## Shorter HN body (recommended)

I built **QDock**, a native macOS menu bar app for tracking Claude Code + Codex quota usage.

I made it after repeatedly getting surprise lockouts during coding sessions.

Security/trust choices:

- manual tokens are stored in macOS Keychain
- Claude detection is file/CLI based (no keychain access during detection)
- Codex integration uses local `codex app-server` over stdio JSON-RPC
- installer verifies DMG SHA-256 checksums and aborts on mismatch/missing checksum

Current limitation: releases are currently unsigned and not notarized.

I would love feedback on security assumptions and onboarding friction.

Repo: https://github.com/altansaid/QDock

## First comment draft

Security notes for reviewers:

- Keychain storage for manual tokens (`kSecAttrAccessibleWhenUnlocked`).
- Installer verifies DMG SHA-256 and aborts when checksum asset is missing.
- No analytics SDK dependency in the Swift package; network usage is limited to provider/update flows.
- I should be explicit: releases are currently unsigned and not notarized, so please evaluate with that in mind.

## Code references used for the security statements

- `QDock/Services/KeychainService.swift:32`
- `QDock/Services/ClaudeCodeDetector.swift:4`
- `QDock/Services/ClaudeCodeDetector.swift:68`
- `QDock/Providers/ClaudeCode/ClaudeCodeProvider.swift:263`
- `QDock/Services/CodexAppServer.swift:3`
- `QDock/Services/CodexAppServer.swift:26`
- `QDock/Services/AppUpdateService.swift:113`
- `installer/bin/qdock-installer.js:211`
- `.github/workflows/release.yml:49`
- `docs/release.md:39`
