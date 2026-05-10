# HavenOS

HavenOS turns a Mac mini into a private home library for books, music, movies, and files.

It is a native macOS app for people who want the usefulness of self-hosted media services without the usual server-admin work. HavenOS installs, configures, starts, monitors, updates, and backs up real open-source services on your Mac, then presents them as simple user-facing capabilities.

No Docker setup, no terminal recipes, no PATH debugging, and no need to understand launch agents or service configuration before your library is usable.

## What HavenOS Does

HavenOS gives your Mac a small home-server brain while keeping the experience Mac-like:

- Choose a capability: Books, Music, Movies, or Files.
- Pick folders with native macOS folder pickers.
- Let HavenOS install and configure the right open-source service.
- Use the native HavenOS tab for setup, status, folders, credentials, scans, backups, and updates.
- Open the browser UI only when the underlying service is better for a specific task.

HavenOS does not replace the open-source projects it manages. It wraps them in one coherent local-first experience.

## Features

### Books

HavenOS manages Kavita for ebooks, comics, manga, and PDFs.

- Library folder setup from the native app
- Account creation and reconnect flow
- Library rescan controls
- Device access information
- Import warnings in plain language
- Backup-aware library and configuration handling

### Music

HavenOS manages Navidrome for private music streaming.

- Music folder setup
- Managed account flow
- Artist, album, and track status
- Scan controls
- Device credentials for Subsonic-compatible clients
- Backup-aware library and credential handling

### Movies

HavenOS manages Jellyfin for movies and TV.

- Movie folder setup
- Managed account flow
- Native status and setup UI
- Metadata and library scan controls
- Browser handoff for playback and advanced library management
- Jellyfin FFmpeg support for media handling

### Files

HavenOS manages File Browser for simple file access from other devices.

- Multiple served folder roots
- Native file browsing surface
- Create folders, rename items, and move files to Trash
- Device access credentials
- Backup scope follows selected roots

### Backups

HavenOS tracks protection by capability instead of asking users to think in hidden service folders.

- Backup destination picker
- Capability-aware backup scope
- Per-capability protection state
- Backup health warnings
- Manifest-based backup records

### Updates

There are two update systems:

- Service updates: HavenOS can check upstream releases for managed services and update them safely.
- App updates: HavenOS uses Sparkle 2 for future self-updates of the macOS app.

## Download

The public website should offer a signed and notarized `HavenOS.dmg` download.

Current public builds are intended for:

- macOS 26 or newer
- Apple Silicon Macs

For direct distribution outside the Mac App Store, the app must be signed with a Developer ID Application certificate, notarized by Apple, and distributed as a DMG.

## Why This Exists

Self-hosted media tools are powerful, but the setup cost is often too high for normal home use. Each service has its own install guide, ports, accounts, folders, launch behavior, update process, and backup assumptions.

HavenOS turns those moving parts into a consistent macOS workflow:

- "Add Books"
- "Choose your folder"
- "Create account"
- "Start"
- "Back up"
- "Open from another device"

The goal is not to hide open source. The goal is to make it feel dependable enough for a home library that keeps running after setup day.

## Project Status

HavenOS is an active early-stage macOS app.

Implemented areas include:

- Native SwiftUI app shell
- Books, Music, Movies, and Files capability surfaces
- launchd-based service lifecycle
- Artifact download, install, and update pipeline
- Capability-aware backup model
- Topbar status menu
- Sparkle app-update integration groundwork
- DMG build, signing, and notarization scripts
- Landing page for public distribution

Expect rough edges while distribution, app updates, and the public download flow settle.

## Open Source Credits

HavenOS is released under the MIT License.

HavenOS uses or manages the following open-source projects:

| Project | Role | License |
|---|---|---|
| [Sparkle](https://github.com/sparkle-project/Sparkle) | macOS app update framework | MIT License |
| [Swift Argument Parser](https://github.com/apple/swift-argument-parser) | command-line parsing for `havenctl` | Apache License 2.0 |
| [Kavita](https://github.com/Kareadita/Kavita) | books, comics, and manga service | GNU GPL v3 |
| [Navidrome](https://github.com/navidrome/navidrome) | music streaming service | GNU GPL v3 |
| [Jellyfin](https://github.com/jellyfin/jellyfin) | movies and TV streaming service | GNU GPL v2 |
| [Jellyfin FFmpeg](https://github.com/jellyfin/jellyfin-ffmpeg) | media playback and transcoding helper | LGPL/GPL, depending on build |
| [File Browser](https://github.com/filebrowser/filebrowser) | browser-based file access service | Apache License 2.0 |

Each project remains governed by its own license and upstream terms.

## Repository Layout

| Module | Purpose |
|---|---|
| `HavenCore` | Domain models, JSON spec loading, planning, state persistence |
| `HavenExecutor` | End-to-end orchestration: plan, prepare, install, start, stop, status |
| `HavenRuntimes` | Runtime adapter protocol and built-in adapters |
| `HavenLaunchd` | launchd job modeling, plist generation, lifecycle management via `launchctl` |
| `HavenInstaller` | Artifact fetch, cache, extraction, placement, and updates |
| `HavenBackup` | Capability-aware backup, scheduling, health, and manifests |
| `HavenAppKit` | SwiftUI app views, native capability facades, backup UI, and settings |
| `HavenApp` | Thin SwiftUI app entry point |
| `HavenCLIKit` | CLI command definitions |
| `HavenCLI` | Thin executable entry point for `havenctl` |

## Architecture

HavenOS organizes services around three nested concepts:

```text
Capability -> Bundle -> RuntimeUnit
```

- **Capability**: a user-facing feature, such as Books, Music, Movies, or Files.
- **Bundle**: a deployable implementation of one capability.
- **RuntimeUnit**: a launchable process with lifecycle configuration, ports, health checks, dependencies, and artifacts.

Users think in capabilities. HavenOS resolves the implementation details.

The execution flow is:

```text
Specs -> Planner -> RuntimeAdapters -> LaunchdJobs -> launchd
```

HavenOS does not run services directly. It plans desired state, prepares artifacts and environments, then delegates execution to macOS through launchd.

## Build From Source

Requirements:

- macOS 26+
- Swift 6.2+
- Xcode 26+

Build the Swift package:

```bash
swift build
```

Build the macOS app wrapper:

```bash
./Scripts/build-app.sh --configuration release
```

The app bundle is written to:

```text
.build/app/HavenOS.app
```

Build a drag-to-Applications DMG:

```bash
./Scripts/build-dmg.sh --configuration release
```

The DMG is written to:

```text
.build/app/HavenOS.dmg
```

You can also open `Haven.xcodeproj` and build the `Haven` scheme.

## Signed Release Build

Direct downloads outside the Mac App Store need Developer ID signing plus Apple's notarization ticket. An Apple Distribution certificate is for App Store distribution, not website DMG downloads.

Create a notary profile once:

```bash
xcrun notarytool store-credentials HavenNotary
```

Build, sign, notarize, staple, and verify a DMG:

```bash
./Scripts/build-dmg.sh \
  --configuration release \
  --sign \
  --sign-identity "Developer ID Application: Andrei Panov (KS9Z78DCVM)" \
  --notarize \
  --notary-profile HavenNotary
```

To publish on the landing page, copy the signed DMG to:

```text
LandingPage/HavenOS.dmg
```

## App Updates With Sparkle

HavenOS uses Sparkle 2 for updating `HavenOS.app` itself. This is separate from service updates for managed apps such as Kavita, Navidrome, Jellyfin, and File Browser.

Development builds leave `SUFeedURL` and `SUPublicEDKey` empty in `Sources/HavenApp/Info.plist`, so the app update button is disabled with an explanatory message.

Before shipping a public update-enabled build:

1. Generate a Sparkle EdDSA key with Sparkle's `generate_keys` tool.
2. Add the appcast URL to `SUFeedURL`.
3. Add the public EdDSA key to `SUPublicEDKey`.
4. Increment both `CFBundleShortVersionString` and `CFBundleVersion`.
5. Build, Developer ID sign, notarize, and staple the app and DMG.
6. Package a Sparkle archive separately with `ditto -c -k --sequesterRsrc --keepParent HavenOS.app HavenOS.zip`.
7. Run Sparkle's `generate_appcast` over the release folder and upload the archive, deltas, release notes, and appcast.

The website download should remain a DMG. The Sparkle ZIP is for the update feed.

## CLI

The CLI is mostly for development and automation:

```bash
swift run havenctl install haven.capability.test-library --specs-dir ./Specs --set data_path=/srv/data
swift run havenctl start haven.capability.test-library
swift run havenctl status haven.capability.test-library
swift run havenctl stop haven.capability.test-library
swift run havenctl uninstall haven.capability.test-library
swift run havenctl list
```

## Tests

Run:

```bash
swift test
```

The suite covers domain models, spec loading, planning, state persistence, runtime adapters, launchd job generation, artifact installation, executor lifecycle, rollback, capability facades, service updates, backups, and CLI parsing.

## Contact

Developed by `com///place`.

For support, legal notices, license questions, and EU user enquiries: `atlas-stoker.4s@icloud.com`.
