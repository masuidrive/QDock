# QDock Release Runbook

This runbook describes how maintainers publish DMG releases and npm installer updates.

## Optional GitHub Secrets

- `NPM_TOKEN` publishes `@qdock/installer`. The GitHub Release still succeeds
  when this secret is absent because npm publishing is non-blocking.

## Release Steps

1. Ensure your target branch is green in CI.
2. Create a tag:

```bash
git tag v1.1.0
git push fork v1.1.0
```

3. `Release` workflow will:
- build universal app (`arm64` + `x86_64`)
- ad-hoc sign the app and verify the universal binary
- generate `checksums.txt`
- upload assets to GitHub Release
- generate release notes from commits since the previous tag
- publish `@qdock/installer` to npm

4. Validate on a clean macOS machine:
- `npx @qdock/installer`
- manual DMG installation

## Website Deployment

Website deployment is handled in:
- site URL: `https://qdock.saidaltan.com/`
- source repo: `https://github.com/altansaid/qdocksite`

This repository no longer runs a site deployment workflow.

## Important Notes (Current Setup)

- Releases are ad-hoc signed but not Apple-notarized.
- On first launch, macOS may block the app. Open with Control-click -> `Open`, then allow it in `Privacy & Security`.

## Release Channels

- Stable tags: `vX.Y.Z` -> npm tag `latest`
- Pre-release tags: `vX.Y.Z-beta.N` -> npm tag `next`
