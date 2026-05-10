# HavenOS

A macOS-first service management system built with Swift Package Manager. HavenOS lets users install, configure, start, stop, and monitor self-hosted services on their Mac — without ever needing to understand the underlying tooling, runtimes, or system plumbing.

## Architecture

HavenOS organises services around three nested concepts:

```
Capability → Bundle → RuntimeUnit
```

- **Capability** — a user-facing feature ("Test Library", "DNS Resolver"). This is what users see and choose.
- **Bundle** — a deployable implementation of exactly one capability. Groups settings and references to runtime units.
- **RuntimeUnit** — a single launchable process (native binary or Python app). Owns lifecycle config, port, healthcheck, and dependencies.

Users think in capabilities. HavenOS resolves everything else.

### Execution flow

```
Specs (JSON) → Planner → RuntimeAdapters → LaunchdJobs → launchd
```

HavenOS does not run services directly. It plans desired state, prepares artifacts and environments, then delegates execution to the OS via launchd.

## Modules

| Module | Purpose |
|---|---|
| `HavenCore` | Domain models, JSON spec loading, planning, state persistence |
| `HavenExecutor` | End-to-end orchestrator: plan → prepare → install → start/stop/status |
| `HavenRuntimes` | Runtime adapter protocol + built-in adapters (native, Python) |
| `HavenLaunchd` | launchd job modeling, plist generation, lifecycle management via launchctl |
| `HavenInstaller` | Artifact fetch, cache, and placement into HavenOS-managed directories |
| `HavenBackup` | Capability-aware backup, scheduling, health, and manifests |
| `HavenAppKit` | SwiftUI app views, native capability facades, backup UI, and settings |
| `HavenApp` | Thin SwiftUI app entry point |
| `HavenCLIKit` | CLI command definitions (ArgumentParser) |
| `HavenCLI` | Thin executable entry point (`havenctl`) |

## Getting Started

### Build

```bash
swift build
```

### Build the macOS App

Open `HavenOS.xcodeproj` and build the `HavenOS` scheme to produce a normal `HavenOS.app` bundle.

You can also build the app wrapper from the command line:

```bash
./Scripts/build-app.sh --configuration release
```

The command-line bundle is written to `.build/app/HavenOS.app` by default.

To build a drag-to-Applications installer image:

```bash
./Scripts/build-dmg.sh --configuration release
```

The DMG is written to `.build/app/HavenOS.dmg` by default.

For public GitHub downloads, use a Developer ID Application certificate and
notarize the app and DMG:

```bash
xcrun notarytool store-credentials HavenNotary
./Scripts/build-dmg.sh --configuration release --sign --sign-identity "Developer ID Application: Andrei Panov (KS9Z78DCVM)" --notarize --notary-profile HavenNotary
```

`Apple Distribution` certificates are for App Store distribution. Direct DMG
downloads need Developer ID signing plus Apple's notarization ticket, otherwise
Gatekeeper can show an "Apple could not verify" warning.

### App Updates

HavenOS uses Sparkle 2 for updating `HavenOS.app` itself. This is separate from HavenOS's service update system, which updates managed services such as Kavita, Navidrome, and Jellyfin.

Development builds leave `SUFeedURL` and `SUPublicEDKey` empty in `Sources/HavenApp/Info.plist`, so the Settings update button is disabled with an explanatory message. Before shipping a public update-enabled build:

1. Generate a Sparkle EdDSA key with Sparkle's `generate_keys` tool.
2. Add the appcast URL to `SUFeedURL`.
3. Add the public EdDSA key to `SUPublicEDKey`.
4. Increment both `CFBundleShortVersionString` and `CFBundleVersion`.
5. Build, Developer ID sign, notarize, and staple the app and DMG with `./Scripts/build-dmg.sh --configuration release --sign --sign-identity "Developer ID Application: ..." --notarize --notary-profile HavenNotary`.
6. Package a Sparkle archive separately with `ditto -c -k --sequesterRsrc --keepParent HavenOS.app HavenOS.zip`.
7. Run Sparkle's `generate_appcast` over the release folder and upload the archive, deltas, release notes, and appcast.

Users on builds before Sparkle integration need one manual update to a Sparkle-enabled `HavenOS.app`; later releases can update from Settings.

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

The suite covers domain models, spec loading, planning, state persistence, runtime adapters, launchd job generation, artifact installation, executor lifecycle, rollback, capability facades, service updates, backups, and CLI parsing.

## Requirements

- macOS 26+
- Swift 6.2+

## Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) 1.3+ — CLI argument parsing
