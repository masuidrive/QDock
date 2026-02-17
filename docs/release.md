# QDock Release Runbook

This runbook describes how maintainers publish DMG releases and npm installer updates.

## Required GitHub Secrets

- `NPM_TOKEN`

For site deployment workflow:

- `VERCEL_TOKEN`
- `VERCEL_ORG_ID`
- `VERCEL_PROJECT_ID`

## Release Steps

1. Ensure your target branch is green in CI.
2. Create a tag:

```bash
git tag v1.1.0
git push origin v1.1.0
```

3. `Release` workflow will:
- build universal app (`arm64` + `x86_64`)
- generate `checksums.txt`
- upload assets to GitHub Release
- publish `@qdock/installer` to npm

4. Validate on a clean macOS machine:
- `npx @qdock/installer`
- manual DMG installation

## Important Notes (Current Setup)

- Releases are currently unsigned and not notarized.
- On first launch, macOS may block the app. Open with Control-click -> `Open`, then allow it in `Privacy & Security`.

## Release Channels

- Stable tags: `vX.Y.Z` -> npm tag `latest`
- Pre-release tags: `vX.Y.Z-beta.N` -> npm tag `next`
