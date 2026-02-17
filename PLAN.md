# QDock — macOS Menu Bar Usage Tracker

## Vision
A lightweight, native macOS menu bar app that lets you instantly see your AI API usage (tokens, costs) across multiple providers — Claude Code, Cursor, Antigravity, OpenAI, and more.

### Zero-Config Claude Code Integration
**No API key needed!** QDock automatically detects your Claude Code installation and reads usage data directly from local files:
- OAuth credentials from macOS Keychain (`"Claude Code-credentials"`)
- Session transcripts from `~/.claude/projects/<path>/<uuid>.jsonl`
- Aggregated stats from `~/.claude/stats-cache.json`
- Account info from `~/.claude.json`

When you open QDock, it instantly shows your Claude Code sessions with per-session token counts, model breakdown, git branch, project name, and estimated cost — all without any setup.

---

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│              macOS Menu Bar                   │
│          [📊 QDock Icon]                     │
└──────────────┬──────────────────────────────┘
               │ click
┌──────────────▼──────────────────────────────┐
│            Popover Window                    │
│  ┌────────────────────────────────────────┐  │
│  │  Today's Usage        [⟳] [⚙]        │  │
│  │  ─────────────────────────────────────│  │
│  │  Anthropic (Claude)         $12.34    │  │
│  │  ██████████░░░░  45K in / 12K out     │  │
│  │                                        │  │
│  │  OpenAI                     $3.21     │  │
│  │  ████░░░░░░░░░░  12K in / 3K out      │  │
│  │                                        │  │
│  │  OpenRouter                 $1.05     │  │
│  │  ██░░░░░░░░░░░░  5K in / 1K out       │  │
│  │  ─────────────────────────────────────│  │
│  │  Total                     $16.60     │  │
│  │  ─────────────────────────────────────│  │
│  │  [Daily ▾]  📈 7-day trend chart      │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| UI Framework | SwiftUI | Native, lightweight, modern |
| System Integration | AppKit (NSStatusItem + NSPopover) | Full control over popover behavior |
| Charts | Swift Charts | Native, interactive, macOS 14+ |
| Networking | URLSession + async/await | Built-in, no dependencies |
| Storage | @AppStorage + Keychain | Preferences in UserDefaults, secrets in Keychain |
| Min Target | macOS 14 (Sonoma) | @Observable, better Charts, modern APIs |
| Architecture | MVVM + Protocol-based Providers | Clean separation, easy to extend |

---

## Provider System

### Protocol Design

```swift
protocol UsageProvider: Identifiable, ObservableObject {
    var id: String { get }
    var name: String { get }
    var iconName: String { get }
    var isEnabled: Bool { get set }
    var isConfigured: Bool { get }

    func fetchUsage(for period: UsagePeriod) async throws -> UsageData
    func validate() async throws -> Bool
}
```

### Supported Providers (v1)

| Provider | API Endpoint | Auth |
|----------|-------------|------|
| **Anthropic** | Admin API `/v1/organizations/usage_report/messages` + `/cost_report` | Admin API Key (`sk-ant-admin...`) |
| **OpenAI** | `/v1/organization/usage` (Dashboard API) | API Key |
| **OpenRouter** | `/api/v1/auth/key` (usage info) | API Key |

### Future Providers
- Google (Vertex AI / Gemini API)
- AWS Bedrock
- Custom/Self-hosted (user-defined endpoint)

---

## Data Models

```swift
struct UsageData {
    let provider: String
    let period: UsagePeriod
    let totalCostUSD: Decimal
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let breakdown: [UsageBreakdown]  // per-model breakdown
    let fetchedAt: Date
}

struct UsageBreakdown {
    let model: String
    let costUSD: Decimal
    let inputTokens: Int
    let outputTokens: Int
}

enum UsagePeriod: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case thisMonth = "This Month"
}
```

---

## UI Screens

### 1. Main Dashboard (Popover)
- Provider-by-provider usage summary
- Total cost across all providers
- Token counts (input/output/cached)
- Miniature 7-day trend chart
- Period selector (Today / 7 Days / 30 Days / This Month)
- Refresh button (manual)
- Settings gear icon

### 2. Settings Window
- **Providers tab**: Enable/disable providers, enter API keys
- **Display tab**: Refresh interval, show/hide cost in menu bar text
- **General tab**: Launch at login, appearance

### 3. Detail View (click on a provider)
- Per-model breakdown
- Daily usage chart (Swift Charts)
- Cache hit rate
- Top models by cost

---

## Key Features

### Core
- [x] Menu bar icon with optional cost display
- [x] Click-to-open popover with usage dashboard
- [x] Manual refresh button
- [x] Auto-refresh (configurable: 5min / 15min / 30min / 1hr / manual only)
- [x] Multi-provider support with provider protocol
- [x] Secure API key storage in macOS Keychain

### Polish
- [x] Period selector (today/week/month)
- [x] Per-model breakdown drill-down
- [x] 7-day trend mini-chart
- [x] Launch at login
- [x] Loading states & error handling
- [x] Empty states with setup guidance

### Extensibility
- [x] Provider protocol for adding new providers
- [x] Custom provider support (user-defined API endpoint)
- [x] Configurable display preferences per provider

---

## File Structure

```
QDock/
├── Package.swift
├── QDock/
│   ├── App/
│   │   ├── QDockApp.swift                 # @main, MenuBarExtra setup
│   │   ├── AppDelegate.swift              # NSStatusItem + NSPopover
│   │   └── AppState.swift                 # Central @Observable state
│   ├── Models/
│   │   ├── UsageData.swift                # Usage data models
│   │   ├── UsagePeriod.swift              # Time period enum
│   │   └── ProviderConfig.swift           # Provider configuration
│   ├── Providers/
│   │   ├── UsageProvider.swift            # Provider protocol
│   │   ├── ProviderManager.swift          # Manages all providers
│   │   ├── Anthropic/
│   │   │   ├── AnthropicProvider.swift    # Anthropic Admin API
│   │   │   └── AnthropicModels.swift      # API response models
│   │   ├── OpenAI/
│   │   │   ├── OpenAIProvider.swift       # OpenAI usage API
│   │   │   └── OpenAIModels.swift         # API response models
│   │   └── OpenRouter/
│   │       ├── OpenRouterProvider.swift   # OpenRouter API
│   │       └── OpenRouterModels.swift     # API response models
│   ├── Services/
│   │   ├── KeychainService.swift          # Secure API key storage
│   │   ├── RefreshService.swift           # Auto-refresh timer
│   │   └── NetworkClient.swift            # Shared URLSession wrapper
│   ├── Views/
│   │   ├── Dashboard/
│   │   │   ├── DashboardView.swift        # Main popover content
│   │   │   ├── ProviderRowView.swift      # Single provider summary
│   │   │   ├── UsageSummaryView.swift     # Total summary header
│   │   │   └── TrendChartView.swift       # Mini 7-day chart
│   │   ├── Detail/
│   │   │   ├── ProviderDetailView.swift   # Per-provider detail
│   │   │   └── ModelBreakdownView.swift   # Per-model table
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift         # Settings window
│   │   │   ├── ProvidersSettingsView.swift # Provider config
│   │   │   ├── DisplaySettingsView.swift  # Display preferences
│   │   │   └── GeneralSettingsView.swift  # General settings
│   │   └── Common/
│   │       ├── TokenCountView.swift       # Token display component
│   │       ├── CostBadgeView.swift        # Cost badge component
│   │       ├── RefreshButton.swift        # Refresh button
│   │       └── EmptyStateView.swift       # Empty/setup state
│   └── Resources/
│       ├── Assets.xcassets                # App icons, colors
│       └── Info.plist                     # LSUIElement = true
└── README.md
```

---

## Anthropic API Integration Details

### Authentication
- Requires **Admin API Key** (`sk-ant-admin...`)
- Only org admins can create these keys
- Header: `x-api-key: <key>` + `anthropic-version: 2023-06-01`

### Endpoints Used

**1. Usage Report** — Token counts
```
GET /v1/organizations/usage_report/messages
?starting_at=2026-02-16T00:00:00Z
&ending_at=2026-02-17T00:00:00Z
&group_by[]=model
&bucket_width=1d
```

**2. Cost Report** — Dollar amounts
```
GET /v1/organizations/cost_report
?starting_at=2026-02-16T00:00:00Z
&ending_at=2026-02-17T00:00:00Z
&group_by[]=description
```

### Data Freshness
- Usage data: ~5 minute delay
- Recommended polling: ≥ 1 minute intervals
- Our default: 15 minutes auto-refresh

---

## Development Phases

### Phase 1: Foundation (MVP)
- Project setup with SwiftUI + AppKit
- Menu bar icon + popover
- Anthropic provider (usage + cost)
- Basic dashboard with provider rows
- Manual refresh
- Keychain storage for API keys
- Settings window (provider config only)

### Phase 2: Polish
- Auto-refresh with configurable intervals
- Period selector
- Per-model breakdown view
- 7-day trend chart
- Loading/error/empty states
- Launch at login

### Phase 3: Multi-Provider
- OpenAI provider
- OpenRouter provider
- Provider enable/disable toggles
- Aggregated total across providers

### Phase 4: Distribution
- App icon design
- DMG creation + notarization
- Homebrew Cask formula
- Sparkle auto-updates
