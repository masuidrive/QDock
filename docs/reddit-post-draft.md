# Reddit Drafts - QDock

## Before posting

- Check each subreddit rules first (self-promotion thresholds differ).
- Be explicit that you built the tool.
- Ask for feedback, not upvotes.

## Draft 1: r/macapps

### Title

I built a macOS menu bar app for Claude + Codex quota tracking (open source)

### Post

I built **QDock**, a native macOS menu bar app that tracks Claude Code and Codex usage/quota in real time.

I made it because I kept getting surprised by rate limits in the middle of coding sessions.

What it does:
- shows current usage windows in the menu bar
- supports both Claude and Codex providers
- adapts refresh interval based on usage pressure
- works as a lightweight menu bar utility (no Dock icon)

Security/trust choices:
- manual tokens are stored in macOS Keychain
- installer verifies SHA-256 checksums
- source is fully open

Limitation (being transparent):
- releases are currently unsigned and not notarized yet

If this is useful to you, I would really value feedback on onboarding and reliability.

Repo: https://github.com/altansaid/QDock

## Draft 2: r/opensource

### Title

Show Reddit: QDock - open-source macOS quota tracker for Claude Code + Codex

### Post

Open-sourced a small tool I use daily: **QDock**.

It is a macOS menu bar app for tracking Claude Code and Codex usage so you can see quota pressure before lockout.

I focused on simple architecture and transparent behavior:
- provider model for Claude/Codex
- local detection + periodic refresh
- stale-cache fallback when provider calls fail
- Keychain storage for manual tokens
- checksum verification in installer

Known gap:
- release signing/notarization is not done yet (planned)

I would appreciate technical feedback on:
1. security model and trust boundaries
2. provider abstraction design
3. release/update hardening priorities

Repo: https://github.com/altansaid/QDock

## Draft 3: r/ClaudeAI or r/OpenAI

### Title

macOS menu bar tracker for Claude/Codex usage - looking for feedback

### Post

I built **QDock** to solve one pain point: unexpectedly hitting Claude/Codex limits while coding.

It is a macOS menu bar app that shows usage windows and risk level in real time.

Highlights:
- Claude + Codex support
- quick auth status visibility
- local app with lightweight UI
- open-source repo

Security notes:
- manual tokens go to macOS Keychain
- installer validates SHA-256 checksums
- no analytics SDK in the Swift package

Current limitation:
- releases are unsigned/not notarized for now

Would love concrete feedback from daily Claude/Codex users.

Repo: https://github.com/altansaid/QDock

## Optional first comment (for transparency)

I am the author of QDock.

If you review it, please look critically at:
- keychain/token flow
- release/install trust model
- what would make you personally trust/use it in daily work

I am actively iterating based on real user feedback.
