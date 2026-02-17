# QDock Installation Guide

QDock supports macOS 14+.

## Option 1: Install with `npx` (Recommended)

```bash
npx @qdock/installer
```

Useful flags:

- `--channel stable|beta`
- `--dir /Applications` (default)
- `--no-launch`
- `--verbose`

## Option 2: Download DMG

1. Open the latest release page:
   `https://github.com/altansaid/macOs-app/releases/latest`
2. Download `QDock-vX.Y.Z-mac-universal.dmg`.
3. Drag `QDock.app` to `Applications`.
4. Open QDock.

## Verify Release Integrity

Every release includes `checksums.txt`.

```bash
shasum -a 256 QDock-vX.Y.Z-mac-universal.dmg
```

Compare with the checksum in `checksums.txt`.

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
- Gatekeeper warning: open QDock with Control-click -> `Open`, then allow it in `Privacy & Security`.
