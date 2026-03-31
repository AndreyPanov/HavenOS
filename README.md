# Haven

A macOS-first service management system built with Swift Package Manager. Haven lets users install, configure, start, stop, and monitor self-hosted services on their Mac — without ever needing to understand the underlying tooling, runtimes, or system plumbing.

## Architecture

Haven organises services around three nested concepts:

```
Capability → Bundle → RuntimeUnit
```

- **Capability** — a user-facing feature ("Test Library", "DNS Resolver"). This is what users see and choose.
- **Bundle** — a deployable implementation of exactly one capability. Groups settings and references to runtime units.
- **RuntimeUnit** — a single launchable process (native binary or Python app). Owns lifecycle config, port, healthcheck, and dependencies.

Users think in capabilities. Haven resolves everything else.

### Execution flow

```
Specs (JSON) → Planner → RuntimeAdapters → LaunchdJobs → launchd
```

Haven does not run services directly. It plans desired state, prepares artifacts and environments, then delegates execution to the OS via launchd.

## Modules

| Module | Purpose |
|---|---|
| `HavenCore` | Domain models, JSON spec loading, planning, state persistence |
| `HavenExecutor` | End-to-end orchestrator: plan → prepare → install → start/stop/status |
| `HavenRuntimes` | Runtime adapter protocol + built-in adapters (native, Python) |
| `HavenLaunchd` | launchd job modeling, plist generation, lifecycle management via launchctl |
| `HavenInstaller` | Artifact fetch, cache, and placement into Haven-managed directories |
| `HavenCLIKit` | CLI command definitions (ArgumentParser) |
| `HavenCLI` | Thin executable entry point (`havenctl`) |

## Getting Started

### Build

```bash
swift build
```

### Run the CLI

```bash
swift run havenctl install haven.capability.test-library --specs-dir ./Specs --set data_path=/srv/data
swift run havenctl start haven.capability.test-library
swift run havenctl status haven.capability.test-library
swift run havenctl stop haven.capability.test-library
swift run havenctl uninstall haven.capability.test-library
swift run havenctl list
```

### Test

```bash
swift test
```

316 tests across 8 test targets covering domain models, spec loading, planning, state persistence, runtime adapters, launchd job generation, artifact installation, executor lifecycle, rollback, and CLI parsing.

## Requirements

- macOS 13+
- Swift 5.9+

## Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) 1.3+ — CLI argument parsing
