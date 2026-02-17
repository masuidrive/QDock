# QDock Release Runbook

This runbook describes how maintainers publish signed and notarized releases.

## Required GitHub Secrets

- `APPLE_CERT_P12_BASE64`
- `APPLE_CERT_PASSWORD`
- `APPLE_DEVELOPER_ID_APPLICATION`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `NPM_TOKEN`

For site deployment workflow:

- `VERCEL_TOKEN`
- `VERCEL_ORG_ID`
- `VERCEL_PROJECT_ID`

## Release Steps

1. Ensure `main` is green.
2. Create a tag:

```bash
git tag v1.1.0
git push origin v1.1.0
```

3. `Release` workflow will:
- build universal app (`arm64` + `x86_64`)
- sign app and DMG
- notarize DMG
- staple tickets
- generate `checksums.txt`
- upload assets to GitHub Release
- publish `@qdock/installer` to npm

4. Validate on a clean macOS machine:
- `npx @qdock/installer`
- manual DMG installation

## Release Channels

- Stable tags: `vX.Y.Z` -> npm tag `latest`
- Pre-release tags: `vX.Y.Z-beta.N` -> npm tag `next`
