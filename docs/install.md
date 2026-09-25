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
4. Try opening `QDock.app` once. macOS may block it because the release is not
   Apple-notarized.
5. Open **System Settings > Privacy & Security**, scroll to **Security**, click
   **Open Anyway** next to QDock, authenticate, and confirm **Open**.
6. In QDock, open **Settings > General** and enable **Launch at login** if desired.

The release is ad-hoc signed but not Apple-notarized. Apple documents the
**Open Anyway** flow in [Open apps safely on your Mac](https://support.apple.com/102445).
Control-clicking **Open** alone may not override Gatekeeper on current macOS.

If **Open Anyway** is unavailable, use the checksum-verified `npx` installation
above. It downloads through Node.js instead of a browser and does not retain the
browser-added quarantine attribute. On a managed Mac, an administrator policy
may still prevent unnotarized apps from running.

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
- Gatekeeper warning: first try to open QDock, then use **System Settings > Privacy & Security > Open Anyway**. If that option is unavailable, use the `npx` installation method or contact the Mac administrator.
- Claude is missing: run `claude auth status`, sign in with `claude auth login`, then refresh QDock.
