<!-- meta: created=2026-02-25 updated=2026-03-06 checked=never -->
# Specification Index

## Directory Structure

```
spec/
├── README.md
├── meta/              # Overall design
│   ├── architecture.md
│   ├── viewmodel-lifecycle.md
│   ├── webview-coordinator.md
│   └── protocols.md
├── data/              # Data models & settings
│   ├── settings.md
│   ├── usage-store.md
│   ├── usage-fetcher.md
│   ├── token-store.md
│   └── alert.md
├── ui/                # UI components
│   ├── app-windows.md
│   ├── menu-content.md
│   └── mini-usage-graph.md
├── analysis/          # Analysis page
│   ├── overview.md
│   ├── analysis-scheme-handler.md
│   └── analysis-exporter.md
├── predict/           # Cost estimation
│   └── jsonl-cost.md
├── widget/            # Widget
│   └── design.md
└── tools/             # Tools & scripts
    └── build-and-install.md
```

## Meta

| File | Description |
|------|-------------|
| [meta/architecture.md](meta/architecture.md) | Overall design, data flow, components |
| [meta/viewmodel-lifecycle.md](meta/viewmodel-lifecycle.md) | UsageViewModel lifecycle (init, fetch, state) |
| [meta/webview-coordinator.md](meta/webview-coordinator.md) | WebViewCoordinator spec-v2.1 (WKNavigationDelegate/WKUIDelegate, OAuth popup) |
| [meta/protocols.md](meta/protocols.md) | DI protocol definitions (7 protocols + default implementations) |

## Data Models

| File | Description |
|------|-------------|
| [data/settings.md](data/settings.md) | Settings spec (JSON persistence) |
| [data/usage-store.md](data/usage-store.md) | UsageStore spec-v2.1 (SQLite usage history storage) |
| [data/usage-fetcher.md](data/usage-fetcher.md) | UsageFetcher spec-v2.1 (JS 1-script fetch, org ID retrieval, session detection) |
| [data/token-store.md](data/token-store.md) | TokenStore spec-v2.1 (SQLite token DB, incremental sync, upsert) |
| [data/alert.md](data/alert.md) | Alert spec-v2.1 (AlertChecker + NotificationManager, threshold evaluation, duplicate notification prevention) |

## UI Components

| File | Description |
|------|-------------|
| [ui/app-windows.md](ui/app-windows.md) | App Windows spec-v2.1 (menu bar label, graph, window management) |
| [ui/menu-content.md](ui/menu-content.md) | MenuContent spec-v2.1 (dropdown menu UI) |
| [ui/mini-usage-graph.md](ui/mini-usage-graph.md) | MiniUsageGraph spec-v2.1 (Canvas graph drawing, step interpolation, area fill) |

## Cost Estimation

| File | Description |
|------|-------------|
| [predict/jsonl-cost.md](predict/jsonl-cost.md) | JSONL estimation (Predict) spec |

## Analysis

| File | Description |
|------|-------------|
| [analysis/overview.md](analysis/overview.md) | Analysis page overview (data sources, tabs, empty states) |
| [analysis/analysis-exporter.md](analysis/analysis-exporter.md) | AnalysisExporter spec-v2.1 (HTML/JS template, 12 Decision Tables, 62 cases) |
| [analysis/analysis-scheme-handler.md](analysis/analysis-scheme-handler.md) | AnalysisSchemeHandler spec-v2.1 (cut:// scheme handler) |

## Widget

| File | Description |
|------|-------------|
| [widget/design.md](widget/design.md) | Widget design spec |

## Tools

| File | Description |
|------|-------------|
| [tools/build-and-install.md](tools/build-and-install.md) | build_and_install.py spec (data protection, atomic install, LaunchServices management) |
