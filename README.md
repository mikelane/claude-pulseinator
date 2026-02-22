[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# Claude Pulseinator

Native macOS menubar app (Swift/SwiftUI) showing Claude Code usage stats. Sits in your menubar as Ψ and opens a 720pt-wide popup.

![Pulseinator screenshot](screenshot.png)

## What's in the popup

**Usage Limits (top-left)** — pulled live from the Claude Code OAuth token in your Keychain:
- 5-hour session utilization %
- 7-day all-models utilization %
- 7-day Sonnet utilization %
- Progress bars that go green → yellow → red, reset countdowns ("resets in 2h 14m")

**Today (top-center)** — from `~/.claude/stats-cache.json`:
- Messages, sessions, tokens for the day
- Week totals for messages and tokens
- Data source badge (Local or API)

**Models (top-right)** — stacked bar chart of lifetime token usage by model with per-model counts.

**Time-series charts** — scoped to the selected time window, from SigNoz:
- Token usage (blue area/line)
- CLI:User leverage ratio — Claude's active time divided by your active time (green area/line; hidden when no data)
- Cost in USD (purple area/line)

**SigNoz bar** — 1h / 3h / 12h / 24h window picker, plus scalar totals for that window: sessions, tokens, cost, lines changed, commits, tool decisions.

**Lifetime bar** — total sessions and messages since your first session, last-refresh timestamp.

Auto-refreshes every 60 seconds. Manual refresh button is in the Today panel header.

## Requirements

- macOS 14 Sonoma or later
- Xcode Command Line Tools: `xcode-select --install`
- Claude Code installed (provides `~/.claude/stats-cache.json` and the Keychain token)

**Usage limit bars** require Claude Code to be logged in. The app reads `Claude Code-credentials` directly from the macOS Keychain — no configuration needed.

**Time-series charts** require SigNoz running at `http://127.0.0.1:8080` with Claude Code sending OpenTelemetry metrics to it. Without SigNoz the charts show "No SigNoz data" and everything else still works.

Metrics queried:

| Metric | Used for |
|--------|----------|
| `claude_code.token.usage` | Token totals and time series |
| `claude_code.cost.usage` | Cost totals and time series |
| `claude_code.active_time.total` | Leverage ratio (`type=cli` vs `type=user`) |
| `claude_code.session.count` | Session count |
| `claude_code.lines_of_code.count` | Lines changed |
| `claude_code.commit.count` | Commit count |
| `claude_code.code_edit_tool.decision` | Tool decisions |

**Anthropic Admin API** (optional) — set `ANTHROPIC_ADMIN_KEY` in the environment before launching to pull org-level token usage. Only useful if you're monitoring an org API key; personal accounts return empty data.

## Build and run

```bash
git clone https://github.com/lanemik/claude-pulseinator
cd claude-pulseinator
swift build
.build/debug/Pulseinator
```

## Keep it running

```bash
# Add to ~/.zshrc or ~/.bash_profile:
/path/to/claude-pulseinator/.build/debug/Pulseinator &

# Or add as a Login Item:
# System Settings → General → Login Items
```

## Using a different metrics backend

All backend config is in `Sources/Pulseinator/SigNozClient.swift`:

```swift
private let baseURL = "http://127.0.0.1:8080"
private let apiKey  = "your-signoz-api-key"
```

The actual query is in `queryMetric` (line 167), which POSTs to `/api/v4/query_range` with a SigNoz builder body.

### Hosted SigNoz (cloud)

Change `baseURL` to your cloud URL. The API is identical to self-hosted.

### Local Grafana + Prometheus

Rewrite `queryMetric` to `GET /api/v1/query_range` on your Prometheus instance. Prometheus uses underscores in metric names (`claude_code_token_usage_total`), takes `start`/`end` as Unix seconds rather than milliseconds, and returns `data.result[].values[]` as `[timestamp_seconds, "value_string"]` pairs. No API key header.

### Grafana Cloud

Same as local Prometheus but the endpoint is `https://prometheus-prod-XX.grafana.net/api/prom/api/v1/query_range` with `Authorization: Bearer your-service-account-token`.

### Datadog

Use `POST https://api.datadoghq.com/api/v2/query/timeseries` with `DD-API-KEY` and `DD-APPLICATION-KEY` headers. The request body uses a `formulas`/`queries` structure. Metric names stay dot-separated; tag filters use `{type:cli}` syntax.

## Project structure

```
Sources/Pulseinator/
  PulseinatorApp.swift   — entry point, MenuBarExtra
  DataProvider.swift     — stats-cache.json, Keychain OAuth, Anthropic Admin API
  SigNozClient.swift     — SigNoz /api/v4/query_range queries and time-series logic
  DashboardView.swift    — SwiftUI layout
```

## License

MIT
