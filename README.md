# QDock

A native macOS menu bar app that shows AI coding quota usage in real time (currently Claude Code and Codex CLI).

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![Swift](https://img.shields.io/badge/swift-5.10-orange)
![Status](https://img.shields.io/badge/status-active-success)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Install

### 1) Command line (recommended)

```bash
npx @qdock/installer
```

Optional flags:

- `--channel stable|beta`
- `--dir /Applications`
- `--no-launch`
- `--verbose`

### 2) Download DMG

Download the latest DMG from GitHub Releases:

- [Latest Release](https://github.com/altansaid/QDock/releases/latest)

### 3) Build from source

```bash
git clone https://github.com/altansaid/QDock.git qdock
cd qdock
swift build
swift run QDock
```

## Why QDock

- Native menu bar experience (no Dock icon)
- Multi-provider architecture (Claude Code + Codex CLI)
- Quota windows and color-coded risk levels
- Dynamic refresh behavior based on usage
- Local provider detection with cached fallback data

## Security and Trust

- Release artifacts are built in CI and published with SHA-256 checksums.
- Installer validates DMG checksum when `checksums.txt` is available in the release.
- Manual tokens are stored in macOS Keychain.

## Website

Official website: [qdock.saidaltan.com](https://qdock.saidaltan.com/)
Website source repository: `https://github.com/altansaid/qdocksite`

## Documentation

- Install guide: `docs/install.md`
- Maintainer release runbook: `docs/release.md`

## Development

Requirements:

- macOS 14.0+
- Swift 5.10 (or Xcode 15.4+)

Build:

```bash
swift build
```

## Contributing

1. Fork the repository.
2. Create a feature branch.
3. Make your changes.
4. Run `swift build` to verify.
5. Open a pull request.

## Roadmap

- Expand provider support
- Improve onboarding diagnostics
- Add automated tests for provider behavior and UI state transitions

## License

MIT License. See [`LICENSE`](LICENSE).
