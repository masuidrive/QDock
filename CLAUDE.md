# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is QDock

QDock is a native macOS menu bar app (no Dock icon) that displays AI coding quota usage in real time. It supports multiple providers (Claude Code, OpenAI Codex) via a `QuotaProvider` protocol. Built with Swift 5.10, SwiftUI, macOS 14+, and zero external dependencies.

## Build & Run

```bash
swift build                # Compile — this is the baseline correctness check
swift run QDock            # Run the menu bar app locally
swift package clean        # Clear stale SwiftPM artifacts
```

Release packaging (used by CI):
```bash
./scripts/build_universal_app.sh <version>   # Universal arm64+x86_64 app bundle → dist/
./scripts/create_dmg.sh <version>            # DMG → dist/
```

Release trigger: `git tag vX.Y.Z && git push origin vX.Y.Z` (runs `.github/workflows/release.yml`).

## Testing

No XCTest target exists. `swift build` is the required baseline check. For provider/auth changes, manually verify: missing-auth state in Settings, recovery after CLI login, menu bar update after refresh.

## Architecture

**Entry point:** `QDockApp.swift` → `AppDelegate` sets up NSStatusItem (menu bar) + NSPopover. App runs as `LSUIElement` (no Dock icon).

**State management:** `AppState` is the central `@Observable @MainActor` class. It owns `ProviderManager`, `RefreshService`, `SessionFileWatcher`, and `AppUpdateService`. Views observe `AppState` reactively.

**Provider system:** `QuotaProvider` protocol (`UsageProvider.swift`) defines the contract. Each provider handles its own detection, auth chain, and API communication:
- `ClaudeCodeProvider` — OAuth token from `~/.claude/.credentials.json` → Keychain fallback → manual entry. Fetches from `api.anthropic.com/api/oauth/usage`.
- `CodexProvider` — JSON-RPC via `codex app-server` subprocess. Config from `~/.codex/` → Keychain → manual entry.

`ProviderManager` orchestrates all providers and aggregates `QuotaData`.

**Data model:** `QuotaData` contains `QuotaWindow[]` (session/weekly/model-specific windows). `UsageLevel` enum drives color coding: green (<50%), yellow (50-75%), orange (75-90%), red (90%+).

**Refresh:** `RefreshService` uses dynamic intervals — 60s at high usage, 120s at moderate, 300s when idle. `SessionFileWatcher` monitors `~/.claude/projects/` for new session JSONL files.

**Menu bar:** `AppDelegate.applyMenuBarPresentation` renders a progress circle icon with optional percentage text. Source can be highest-across-providers or a specific provider.

## Coding Conventions

- Swift 5.10, 4-space indentation, macOS 14+ APIs only
- `UpperCamelCase` types, `lowerCamelCase` functions/properties
- `@MainActor` on all UI/state mutation code
- `// MARK:` sections for organization
- Commits: conventional prefixes (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`)
- Secrets go through `KeychainService` only — never log auth headers or credentials

## Adding a New Provider

1. Create a folder under `QDock/Providers/` with the provider name
2. Implement `QuotaProvider` protocol (id, name, detection, auth, fetchQuota)
3. Register in `ProviderManager.setupProviders()`
4. Add UI configuration in `ProvidersSettingsView`
