# QDock Installation Guide

QDock supports macOS 14+.

## Install on Another Mac with `npx` (Recommended)

Requirements: macOS 14 or later and Node.js 18 or later.

```bash
QDOCK_REPO=masuidrive/QDock npx --yes @qdock/installer
```

This downloads the latest release from `masuidrive/QDock`, verifies its SHA-256
checksum, installs `QDock.app` in `/Applications`, and launches it.

Useful flags:

- `--channel stable|beta`
- `--dir /Applications` (default)
- `--no-launch`
- `--verbose`

If the account cannot write to `/Applications`, install for the current user:

```bash
QDOCK_REPO=masuidrive/QDock npx --yes @qdock/installer --dir "$HOME/Applications"
```

## Install on Another Mac from the DMG

1. Open the [latest GitHub Release](https://github.com/masuidrive/QDock/releases/latest).
2. Download `QDock-vX.Y.Z-mac-universal.dmg` and `checksums.txt`.
3. Open the DMG and drag `QDock.app` to `Applications`.
4. On first launch, Control-click `QDock.app`, choose **Open**, and confirm.
5. In QDock, open **Settings > General** and enable **Launch at login** if desired.

The release is ad-hoc signed but not Apple-notarized, so macOS may require the
Control-click launch once on each machine.

## Verify Release Integrity

Every release includes `checksums.txt`.

```bash
shasum -a 256 QDock-vX.Y.Z-mac-universal.dmg
```

Compare with the checksum in `checksums.txt`.

## Provider Setup

QDock reads the existing local CLI authentication. Authenticate each provider
before launching QDock:

```bash
claude auth login
codex login
```

You can verify Claude authentication with:

```bash
claude auth status
```

After login, open QDock and use the refresh button. QDock does not require
copying tokens between machines.

## Build from Source

```bash
git clone https://github.com/masuidrive/QDock.git
cd QDock
swift build
swift run QDock
```

## Uninstall

```bash
rm -rf /Applications/QDock.app
```

If installed to user applications:

```bash
rm -rf ~/Applications/QDock.app
```

## Troubleshooting

- Installer reports `macOS only`: run on macOS 14+.
- Installer cannot write `/Applications`: rerun with `--dir ~/Applications`.
- Gatekeeper warning: Control-click QDock, choose `Open`, then allow it in `Privacy & Security` if prompted.
- Claude is missing: run `claude auth status`, sign in with `claude auth login`, then refresh QDock.
