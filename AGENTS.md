# Repository Guidelines

## Project Structure & Module Organization
- `QDock/` is the macOS app source (Swift Package executable target).
- `QDock/App/`: app lifecycle and global state (`AppDelegate`, `AppState`).
- `QDock/Providers/`: provider integrations (`ClaudeCode/`, `Codex/`, `ProviderManager`).
- `QDock/Services/`: networking, keychain, refresh loop, local detection, app update services.
- `QDock/Views/`: UI grouped by feature (`Dashboard/`, `Detail/`, `Settings/`, `Common/`).
- `QDock/Models/`: shared domain models (usage windows, provider config).
- `scripts/`: release packaging scripts for universal build + DMG.
- `installer/`: `@qdock/installer` npm CLI package.
- `docs/`: install and release documentation.

## Build, Test, and Development Commands
- `swift build`: compile the app and catch type/checking errors.
- `swift run QDock`: run the menu bar app locally.
- `swift package clean`: clear SwiftPM artifacts when builds get stale.
- `./scripts/build_universal_app.sh <version>`: build universal app bundle into `dist/`.
- `./scripts/create_dmg.sh <version>`: package DMG for release assets.
- Release trigger: `git tag vX.Y.Z && git push origin vX.Y.Z` (runs `.github/workflows/release.yml`).

## Coding Style & Naming Conventions
- Swift 5.10, macOS 14+ target, 4-space indentation.
- Types: `UpperCamelCase`; functions/properties: `lowerCamelCase`.
- Prefer small, focused types and keep feature code near its module folder.
- Use `@MainActor` for UI/state mutations and async UI-facing flows.
- Follow existing `// MARK:` organization and keep comments concise, factual.

## Testing Guidelines
- There is currently no committed XCTest target; `swift build` is the required baseline check.
- For provider/auth changes, do manual validation:
  - missing-auth state in `Settings > Providers`
  - recovery flow after CLI login
  - menu bar usage update after refresh
- For release/installer changes, validate install path using `docs/release.md` and `docs/install.md`.

## Commit & Pull Request Guidelines
- Follow the existing conventional style seen in history: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `release:`, `security:`.
- Keep commit scope narrow and message imperative (e.g., `fix: clear stale quota on auth failure`).
- PRs should include:
  - what changed and why
  - manual verification steps/commands
  - screenshots or GIFs for UI-visible changes
  - linked issue (if applicable)

## Security & Configuration Tips
- Never commit tokens, credentials, or machine-local config files.
- Store secrets only through `KeychainService` paths already used in the app.
- Do not add debug logs that expose auth headers or raw credential payloads.
