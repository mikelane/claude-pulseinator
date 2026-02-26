# claude-pulseinator

macOS menu bar app (SwiftUI + AppKit) that shows Claude Code usage stats from SigNoz and the Anthropic OAuth API.

## Build & Run

```bash
swift build                  # compile
pkill -x Pulseinator         # restart (LaunchAgent relaunches automatically)
```

Never run `open .build/debug/Pulseinator` — the LaunchAgent is already managing the process.

## Process Management

The app runs as a LaunchAgent:
- **Plist**: `~/Library/LaunchAgents/com.mikelane.pulseinator.plist`
- **Binary**: `.build/debug/Pulseinator`
- **KeepAlive: true** — killing the process triggers an immediate relaunch
- **Logs**: `/tmp/pulseinator.log`

To restart after a build: `swift build && pkill -x Pulseinator`

Running `open .build/debug/Pulseinator` alongside the LaunchAgent creates duplicate instances. Don't do it.

## Menu Bar Icon Rendering

Always use `NSImage` drawn via AppKit for custom `MenuBarExtra` label icons.
SwiftUI `Canvas` and `ZStack` are **invisible** in the MenuBarExtra label context.

```swift
Image(nsImage: myNSImage)   // ✅ works
Canvas { ... }              // ❌ invisible
ZStack { ... }              // ❌ collapses to zero size
```

## Claude OAuth Credentials

`~/.claude/.credentials.json` is the authoritative credential source.
The keychain entry `Claude Code-credentials` is truncated at ~2012 bytes
(predates mcpOAuth keys) and cannot be parsed as valid JSON.

`readKeychainAccessToken()` already reads the file first with keychain as fallback.
Do not revert this — the keychain fallback exists but will always fail.

## Testing Policy

No test target exists. `swift build` succeeding is the quality gate.
TDD hooks will fire but can be ignored for this project.

## Key Files

| File | Purpose |
|------|---------|
| `Sources/Pulseinator/PulseinatorApp.swift` | App entry point, LaunchAgent state, menu bar icon |
| `Sources/Pulseinator/DashboardView.swift` | Main panel UI |
| `Sources/Pulseinator/DataProvider.swift` | Local stats + OAuth usage limits |
| `Sources/Pulseinator/SigNozClient.swift` | SigNoz time-series queries |

## SigNoz

- URL: `http://127.0.0.1:8080` (local OrbStack instance)
- API key: `~/.config/pulseinator/signoz_api_key` or `$SIGNOZ_API_KEY` env var
- Dashboard UUID: `019b18fc-a5c9-739d-85a5-53ee68f68a08`
