# QDock

A native macOS menu bar app that shows your AI coding quota usage in real time, starting with Claude Code and Codex CLI.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![Swift](https://img.shields.io/badge/swift-5.10-orange)
![Status](https://img.shields.io/badge/status-active-success)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Why This Exists

When you are deep in coding, quota limits are easy to miss.  
QDock keeps usage visible in the menu bar so you can spot risk early, refresh quickly, and avoid sudden lockouts.

## Features

- Native menu bar UX (no Dock icon, fast popover dashboard)
- Multi-provider support (currently Claude Code and Codex CLI)
- Per-provider quota windows (for example session and weekly usage)
- Color-coded usage levels (low, moderate, high, critical)
- Dynamic auto-refresh (faster refresh when usage is high)
- Provider auto-detection from local environment
- Cached fallback data when provider APIs are temporarily unavailable
- Secure token storage in macOS Keychain for manual token entry

## Requirements

- macOS 14.0 or newer
- Swift 5.10 toolchain (or Xcode 15.4+)
- Claude Code CLI (`claude`) if you want Claude usage tracking
- Codex CLI (`codex`) if you want Codex usage tracking

## Quick Start

```bash
git clone https://github.com/altansaid/macOs-app.git
cd macOs-app
swift build
swift run QDock
```

After launch, click the QDock icon in your menu bar.

## Provider Setup

### Claude Code

1. Install Claude Code CLI and complete login once by running `claude` in your terminal.
2. Open QDock Settings -> Providers.
3. Enable `Claude Code`.

If automatic auth is not available, QDock also supports manual token paste in Settings.

### Codex CLI

1. Install Codex CLI:
```bash
npm i -g @openai/codex
```
2. Make sure `codex` is available in `PATH`.
3. Open QDock Settings -> Providers and enable `Codex CLI`.

QDock queries Codex limits through `codex app-server` JSON-RPC.

## Usage

1. Open the popover from the menu bar icon.
2. Review provider tabs and quota windows.
3. Use the refresh button for immediate sync.
4. Open Settings to configure providers, menu bar source, refresh behavior, and launch-at-login.

## Troubleshooting

- QDock icon not visible: check menu bar overflow area and relaunch with `swift run QDock`.
- Claude Code not detected: verify `claude` is installed and run `claude` once to finish authentication.
- Codex not detected: verify `codex` is in your `PATH` and `~/.codex` exists.
- Temporary API failure: QDock may show cached data as stale until next successful refresh.

## Privacy and Security

- QDock reads provider state from local environment (such as `~/.claude` and `~/.codex` when available).
- Manual tokens are stored in macOS Keychain.
- Network calls are only used to fetch usage/quota data from provider endpoints.
- There is no analytics/telemetry subsystem in this repository.

## Project Structure

```text
UsageBar/
  App/         # app lifecycle, menu bar integration, global state
  Providers/   # provider implementations (Claude Code, Codex)
  Services/    # networking, keychain, file watchers, refresh logic
  Views/       # dashboard, detail, settings UI
  Models/      # quota and configuration models
```

## Contributing

Contributions are welcome.

1. Fork the repository.
2. Create a feature branch.
3. Make your changes.
4. Verify build locally:
```bash
swift build
```
5. Open a pull request with a clear summary and screenshots (if UI changed).

## Roadmap

- Add more provider integrations
- Improve onboarding and setup diagnostics
- Add automated tests for providers and UI state flows

## License

Licensed under the MIT License. See [`LICENSE`](LICENSE).

## Last Reviewed

2026-02-17
