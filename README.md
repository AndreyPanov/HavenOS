# Haven

A macOS-first capability management system built with Swift Package Manager.

## Architecture

Haven organises work around three nested concepts:

```
Capability → Bundle → RuntimeUnit
```

### Capability

The leaf unit. A `Capability` describes one discrete piece of functionality
(e.g. "DNS resolver", "HTTP proxy", "file watcher"). It has an identifier,
a human-readable name, and a semver version string.

```swift
Capability(id: "cap.dns", name: "DNS Resolver", version: "1.0.0")
```

### Bundle

A `Bundle` groups related capabilities into a deployable unit.
Everything inside a bundle is resolved, scheduled, and torn down together.
Bundles have a reverse-DNS identifier similar to macOS app bundles.

```swift
Bundle(
    id: "com.example.networking",
    name: "Networking Bundle",
    capabilities: [dnsCap, proxyCap]
)
```

### RuntimeUnit

A `RuntimeUnit` is the live execution context that hosts a bundle. It owns
the lifecycle state machine (`idle → running → stopped / failed`) and is
managed by a runtime adapter from the `HavenRuntimes` module.

```swift
var unit = RuntimeUnit(id: "unit.net.1", bundle: networkingBundle)
unit.start()   // state: .running
unit.stop()    // state: .stopped
```

## Modules

| Module | Purpose |
|---|---|
| `HavenCore` | Domain models: `Capability`, `Bundle`, `RuntimeUnit` |
| `HavenCLI` | `havenctl` command-line tool (ArgumentParser) |
| `HavenLaunchd` | launchd / ServiceManagement integration *(stub)* |
| `HavenRuntimes` | Runtime adapter protocol + built-in adapters *(stub)* |

## Getting Started

### Build

```bash
swift build
```

### Run the CLI

```bash
swift run havenctl status
swift run havenctl list --verbose
```

### Test

```bash
swift test
```

## Requirements

- macOS 13+
- Swift 5.9+

## Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing
