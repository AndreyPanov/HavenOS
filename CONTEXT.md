# Haven — Project Context

## What Haven Is

Haven is a macOS-first service management system. It lets users install, configure, start, stop, and monitor self-hosted services on their Mac — without ever needing to understand the underlying tooling, runtimes, or system plumbing.

**Target:** macOS 13+, Swift 5.9+, Swift Package Manager.

## Core Abstraction Chain

```
Capability → Bundle → RuntimeUnit
```

- **Capability** — a user-facing feature ("Test Library", "DNS Resolver"). Identified by reverse-DNS ID. This is what users see and choose.
- **Bundle** — a deployable implementation of exactly one capability. Groups settings and references to runtime units.
- **RuntimeUnit** — a single launchable process (native binary or Python app). Owns lifecycle, port, healthcheck, dependencies.

Users think in capabilities. Haven resolves everything else.

## Product Rules

### Haven manages all dependencies internally

Haven must fully manage all service dependencies internally. Users must never be asked to install Python, pip, Homebrew, Java, Node, or any other dependency themselves.

- Do not introduce any "manual install" flow.
- Do not depend on PATH for user-installed tools unless strictly internal and hidden behind Haven-managed setup.
- Any runtime-specific setup (interpreters, libraries, runtimes) must happen automatically inside Haven-managed directories.
- UI and user-facing errors must never mention pip, brew, venv, PATH, launchctl, or similar implementation details unless shown in an advanced diagnostics view.
- User-facing language should describe services, not tooling. Say "The service failed to start" not "python3 returned exit code 1".

### Workflow

- Commit after every change.

## Execution Philosophy

Haven does not directly "run commands" as a primary model.

Instead, Haven:

1. Plans desired service state (Planner)
2. Prepares artifacts and environments (Installer / RuntimeAdapters)
3. Delegates execution to the OS (launchd on macOS)

Haven is a planner and orchestrator, not a long-running process supervisor.

All runtime-specific behavior (Python, native binaries, etc.) must be encapsulated inside RuntimeAdapters.

No user-facing flow should expose:
- pip
- python
- brew
- PATH
- launchctl

These are implementation details only.

## Module Map

| Module | Path | Purpose |
|---|---|---|
| `HavenCore` | `Sources/HavenCore/` | Domain models, specs, planning, state — no I/O beyond file state |
| `HavenExecutor` | `Sources/HavenExecutor/` | End-to-end orchestrator: plan → prepare → install → start/stop/status lifecycle |
| `HavenCLIKit` | `Sources/HavenCLIKit/` | CLI command definitions (ArgumentParser) — install, uninstall, start, stop, status, list |
| `HavenCLI` | `Sources/HavenCLI/` | Thin executable entry point (`havenctl`) |
| `HavenLaunchd` | `Sources/HavenLaunchd/` | launchd job modeling + execution controller — plist generation, lifecycle management via launchctl |
| `HavenInstaller` | `Sources/HavenInstaller/` | Artifact fetch, cache, and placement — downloads, extracts, and installs service artifacts into Haven-managed directories |
| `HavenRuntimes` | `Sources/HavenRuntimes/` | Runtime adapter protocol + built-in adapters (native, Python) |

## HavenCore Internal Structure

### Domain (`Sources/HavenCore/Domain/`)

Pure value types with Codable, Equatable, Sendable, validation, and static examples.

| File | Type | Notes |
|---|---|---|
| `Capability.swift` | `Capability` | ID, name, version, summary. Example: `.testLibraryExample` |
| `Bundle.swift` | `Bundle` | ID, name, capabilityID (singular), runtimeUnitIDs, settings. Custom `init(from:)` for optional fields. Example: `.testLibraryBasicExample` |
| `RuntimeUnit.swift` | `RuntimeUnit` | ID, bundleID, runtimeType (native/python), installSource, launchArguments, healthcheck, dependsOn, port, environment. Custom `init(from:)`. Examples: `.testDBExample`, `.testWorkerExample`, `.testWebExample` |
| `Healthcheck.swift` | `Healthcheck` | type (http/tcp/exec), target, intervalSeconds, retries |
| `SettingField.swift` | `SettingField` | key, label, fieldType (string/integer/boolean/path), defaultValue, required. Regex-validated key |
| `ServiceRecord.swift` | `ServiceRecord` | Read-only aggregate of capability + bundle + units. Example: `.testLibraryExample` |
| `ValidationError.swift` | `ValidationError` | Simple Error struct with message |

### Specs (`Sources/HavenCore/Specs/`)

Strict JSON spec loading from a directory tree. Never throws — collects all issues in one pass.

| File | Type | Notes |
|---|---|---|
| `SpecLoader.swift` | `SpecLoader` | Loads from `Capabilities/`, `Bundles/`, `Runtime/` subdirectories. Deduplicates, cross-validates references, runs per-model validation |
| `StrictJSONDecoder.swift` | `StrictJSONDecoder` | Two-pass: JSONSerialization rejects unknown keys, then JSONDecoder decodes. Known key sets per type |
| `SpecRegistry.swift` | `SpecRegistry` | In-memory store: `capabilitiesByID`, `bundlesByID`, `runtimeUnitsByID` |
| `SpecLoadResult.swift` | `SpecLoadResult` | Optional registry + issue array |
| `SpecLoadIssue.swift` | `SpecLoadIssue` | Kind (malformedJSON/unknownField/duplicateID/missingReference/validationFailure), source, detail |

### Planning (`Sources/HavenCore/Planning/`)

Pure planner that resolves intent into a deterministic install plan. No I/O.

| File | Type | Notes |
|---|---|---|
| `Planner.swift` | `Planner` | Resolves capability → bundle → units, validates settings, topological sort with cycle detection, `${placeholder}` template expansion, port assignment |
| `PlanningError.swift` | `PlanningError` | capabilityNotFound, bundleNotFound, runtimeUnitNotFound, requiredSettingMissing, dependencyCycle |
| `TemplateContext.swift` | `TemplateContext` | Key-value bag with `expand(_:)`, `expandValues(in:)`, `expandAll(_:)` for `${placeholder}` substitution |
| `PlannedDirectoryLayout.swift` | `PlannedDirectoryLayout` | `Services/<cap-id>/{data,config,logs,run}` — used during planning |
| `PlannedService.swift` | `PlannedService` | capability + bundle + resolved units + settings + layout |
| `PlannedRuntimeUnit.swift` | `PlannedRuntimeUnit` | Resolved launch args, env, port, healthcheck, dependsOn, template context |
| `PlannedPort.swift` | `PlannedPort` | number + source (spec or settingOverride) |
| `InstallPlan.swift` | `InstallPlan` | Wraps a PlannedService |

### State (`Sources/HavenCore/State/`)

Filesystem layout and persistent state store. Thread-safe, atomic writes.

| File | Type | Notes |
|---|---|---|
| `HavenPaths.swift` | `HavenPaths` | Resolves all paths from a base URL: `State/`, `Downloads/`, `Installed/`, `Services/`, `State/services.json` |
| `ServiceDirectoryLayout.swift` | `ServiceDirectoryLayout` | Codable value type for `Services/<cap-id>/{data,config,logs,run}` |
| `ServiceStatus.swift` | `ServiceStatus` | Enum: installed, running, stopped, failed |
| `StoredServiceState.swift` | `StoredServiceState` | capabilityID, bundleID, installedAt, updatedAt, status, resolvedSettings, portAssignments, runtimeUnitIDs, directoryLayout |
| `StoredPortAssignment.swift` | `StoredPortAssignment` | unitID + port |
| `HavenState.swift` | `HavenState` | Top-level container: `[capabilityID: StoredServiceState]` |
| `StateStore.swift` | `StateStore` | Protocol: load, save, service(for:), upsert, remove |
| `AtomicFileWriter.swift` | `AtomicFileWriter` | Temp file + rename, creates parent dirs |
| `FileStateStore.swift` | `FileStateStore` | JSON-backed, NSLock for thread safety, ISO 8601 dates, tolerates missing file |

## HavenRuntimes Internal Structure (`Sources/HavenRuntimes/`)

Runtime adapter layer that prepares RuntimeUnits for launch. Encapsulates all runtime-specific behavior so upper layers never need to know how native vs Python services differ.

| File | Type | Notes |
|---|---|---|
| `RuntimeAdapter.swift` | `RuntimeAdapter` | Protocol: `prepare(unit:plannedUnit:serviceLayout:)` → `PreparedRuntime`, `teardown(preparedRuntime:serviceLayout:)` |
| `PreparedRuntime.swift` | `PreparedRuntime` | Launch-ready output: executableURL, arguments, environment, workingDirectory, managedDirectories, runtimeType, healthcheck, port, dependsOn |
| `NativeRuntimeAdapter.swift` | `NativeRuntimeAdapter` | Prepares native macOS binaries — resolves executable path from installSource, passes through planned args/env |
| `PythonRuntimeAdapter.swift` | `PythonRuntimeAdapter` | Prepares Haven-managed Python apps — computes per-unit venv under `run/venvs/<unit-id>/`, sets VIRTUAL_ENV, controlled PATH, python3 as interpreter |
| `RuntimeAdapterRegistry.swift` | `RuntimeAdapterRegistry` | Resolves adapter by `RuntimeType`, convenience `prepare()`, `makeDefault()` factory |
| `RuntimeAdapterError.swift` | `RuntimeAdapterError` | Service-oriented errors: missingInstallSource, executableNotFound, missingLaunchArguments, unsupportedRuntimeType, environmentSetupFailed |

Key design rules:
- Adapters are pure preparation — no process execution, no filesystem I/O, no downloads
- `PreparedRuntime` is runtime-agnostic — execution layer treats all runtimes identically
- Python venvs live under `run/venvs/<unit-id>/` within the service directory
- PATH is controlled (venv bin + `/usr/bin:/bin`) — no user PATH leakage
- Error cases use service-oriented language, never mention pip/brew/venv/PATH

## HavenInstaller Internal Structure (`Sources/HavenInstaller/`)

Artifact installer layer that fetches, caches, and places service artifacts in Haven-managed directories. Handles local files and remote downloads, supports executables and archives.

| File | Type | Notes |
|---|---|---|
| `ArtifactSource.swift` | `ArtifactSource` | Enum: `.local(URL)`, `.remote(URL)`. String convenience init (http/https → remote, else → local) |
| `ArtifactFormat.swift` | `ArtifactFormat` | Enum: `.executable`, `.zip`, `.tarGz`. Static `detect(from:)` for extension-based detection |
| `ArtifactDescriptor.swift` | `ArtifactDescriptor` | unitID + source + format — describes what to install and where to get it |
| `ArtifactInstallResult.swift` | `ArtifactInstallResult` | unitID + installDirectory + wasCached — result of a successful installation |
| `ArtifactInstallerError.swift` | `ArtifactInstallerError` | 6 cases: sourceFileNotFound, downloadFailed, extractionFailed, unsupportedFormat, artifactNotFound, installFailed |
| `DownloadClient.swift` | `DownloadClient` | Protocol: `download(from:) → URL`. Enables mock-based testing |
| `URLSessionDownloadClient.swift` | `URLSessionDownloadClient` | Production implementation via URLSession.shared.downloadTask |
| `ArchiveExtractor.swift` | `ArchiveExtractor` | Protocol: `extract(archiveURL:to:format:)`. Enables mock-based testing |
| `ProcessArchiveExtractor.swift` | `ProcessArchiveExtractor` | Production implementation: `/usr/bin/ditto -xk` for ZIP, `/usr/bin/tar -xzf` for tar.gz |
| `ArtifactCache.swift` | `ArtifactCache` | Manages `<base>/Installed/<unit-id>/` directories. isCached, remove, prepareCleanDirectory |
| `ArtifactInstaller.swift` | `ArtifactInstaller` | Primary API: `install(descriptor:)` → `ArtifactInstallResult`, `uninstall(unitID:)`. Orchestrates cache check → source resolution → extraction/copy |

Key design rules:
- Install directories are deterministic: `<base>/Installed/<unit-id>/`
- Cache check avoids duplicate extraction — if directory exists and is non-empty, returns immediately
- `DownloadClient` and `ArchiveExtractor` protocols enable fully isolated mock-based testing
- Uses macOS built-in tools only (`ditto`, `tar`) — no Homebrew or external dependencies
- Cleans up partial extractions on failure
- Cleans up downloaded temp files for remote sources after install
- Error cases use service-oriented language — no ditto/tar/unzip in case names
- Convenience initializer accepts `HavenPaths` to derive cache root and downloads directory

## HavenLaunchd Internal Structure (`Sources/HavenLaunchd/`)

Launchd job modeling and execution layer. Translates `PreparedRuntime` values into deterministic launchd property list definitions and manages their lifecycle through `launchctl`.

### Modeling types

| File | Type | Notes |
|---|---|---|
| `LaunchdJob.swift` | `LaunchdJob` | Models a launchd plist: Label, ProgramArguments, EnvironmentVariables, WorkingDirectory, StandardOutPath, StandardErrorPath, RunAtLoad, KeepAlive. Factory: `make(capabilityID:unitID:preparedRuntime:serviceLayout:)`. Encodes to XML plist via `plistData()` |
| `LaunchdKeepAlivePolicy.swift` | `LaunchdKeepAlivePolicy` | Enum: `.always` (restart unconditionally), `.successfulExit` (restart on non-zero exit), `.none` (no restart). Converts to plist-compatible representation |
| `LaunchdLabel.swift` | `LaunchdLabel` | Deterministic label generation: `app.haven.<capability-id>.<unit-id>` |

### Execution types

| File | Type | Notes |
|---|---|---|
| `LaunchdController.swift` | `LaunchdController` | Primary API: `install(job:)`, `uninstall(label:)`, `start(label:)`, `stop(label:)`, `status(label:)`. Writes plists atomically, delegates to `LaunchctlClient`, parses `launchctl print` output for status |
| `LaunchdPaths.swift` | `LaunchdPaths` | Resolves `~/Library/LaunchAgents/<label>.plist` paths. Injectable for testing |
| `LaunchdJobStatus.swift` | `LaunchdJobStatus` | Observed runtime status: state (installed/running/stopped/notFound), pid, lastExitStatus, label |
| `LaunchctlClient.swift` | `LaunchctlClient` | Protocol: bootstrap, bootout, start, stop, print. Enables mock-based testing |
| `ProcessLaunchctlClient.swift` | `ProcessLaunchctlClient` | Production implementation via Foundation.Process. Targets `gui/<uid>` domain |
| `LaunchdControllerError.swift` | `LaunchdControllerError` | Structured errors: plistSerializationFailed, plistWriteFailed, plistRemoveFailed, loadFailed, unloadFailed, startFailed, stopFailed, statusQueryFailed, jobNotFound |

Key design rules:
- Labels are deterministic and predictable: `app.haven.<cap-id>.<unit-id>`
- Log paths follow convention: `<logs>/<unit-id>.stdout.log`, `<logs>/<unit-id>.stderr.log`
- Default keep-alive policy is `.successfulExit` (restart on crash, not on clean exit)
- Empty environment variables are omitted from the plist
- `KeepAlive = .none` is omitted entirely from the plist
- XML plist serialization via Foundation's `PropertyListSerialization`
- `LaunchctlClient` protocol enables fully isolated testing with `MockLaunchctlClient`
- `LaunchdPaths` is injectable — tests use temp directories instead of real `~/Library/LaunchAgents`
- Controller uses atomic writes (temp file + rename) for plist files
- All `launchctl` commands target `gui/<uid>` (user-session LaunchAgents)
- Error cases use service-oriented language — no `launchctl`/`bootstrap`/`bootout` in case names
- Status parsing extracts PID, exit code, and state from `launchctl print` output

## HavenExecutor Internal Structure (`Sources/HavenExecutor/`)

MVP end-to-end orchestrator that wires together spec loading, planning, runtime preparation, launchd job management, and state persistence into a single API surface.

| File | Type | Notes |
|---|---|---|
| `HavenExecutor.swift` | `HavenExecutor` | Primary API: `install(capabilityID:registry:settings:)`, `uninstall(capabilityID:)`, `start(capabilityID:)`, `stop(capabilityID:)`, `status(capabilityID:)`. Injectable dependencies: HavenPaths, StateStore, RuntimeAdapterRegistry, LaunchdController, ArtifactInstaller (optional) |
| `ExecutorError.swift` | `ExecutorError` | 11 cases: alreadyInstalled, notInstalled, planningFailed, unsupportedRuntime, artifactInstallFailed, preparationFailed, serviceInstallFailed, serviceUninstallFailed, startFailed, stopFailed, statusQueryFailed. All carry capabilityID + optional unitID + detail |
| `ServiceStatusReport.swift` | `ServiceStatusReport`, `UnitStatusReport` | Combines persisted state with live launchd status per unit. Reports capabilityID, bundleID, status, and per-unit state/pid/lastExitStatus |

Key design rules:
- Install flow: guard not installed → Planner.planInstall → create directories → for each unit: reject unsupported runtimes (python) → install artifact (if installer configured) → resolve installed path → prepare runtime → make LaunchdJob → install job → persist state (.installed)
- Uninstall flow: for each unit (reverse order): best-effort stop + uninstall → best-effort remove artifacts → remove state → best-effort remove service directory
- Start/stop operate in dependency order (forward/reverse) and update persisted status
- ArtifactInstaller is optional (nil by default) — when present, artifacts are installed into `Installed/<unit-id>/` and the RuntimeUnit's installSource is resolved to the installed location
- Python runtime units are rejected early with `.unsupportedRuntime` — no artifacts fetched, no launchd calls made
- All operations are synchronous (no async) and throw on failure
- Error cases use service-oriented language — no launchctl/pip/brew/PATH exposure

## HavenCLIKit Internal Structure (`Sources/HavenCLIKit/`)

Real CLI commands wired to HavenExecutor.

| Command | Argument | Options | Notes |
|---|---|---|---|
| `install` | `capabilityID` | `--specs-dir`, `--set key=value`, `--base-dir` | Loads specs, installs capability, prints result |
| `uninstall` | `capabilityID` | `--base-dir` | Uninstalls capability |
| `start` | `capabilityID` | `--base-dir` | Starts all units |
| `stop` | `capabilityID` | `--base-dir` | Stops all units |
| `status` | `capabilityID` | `--base-dir` | Shows per-unit live status |
| `list` | — | `--base-dir` | Lists all installed services from state |

Shared `CommonOptions` group provides `--base-dir` (default `~/.haven`) and factory methods for `HavenExecutor` and `FileStateStore`.

## Filesystem Layout

Under the Haven base directory:

```
<base>/
  State/
    services.json          ← persisted service state
  Downloads/               ← temporary download staging
  Installed/
    <runtime-unit-id>/     ← one per installed runtime unit
      ...                  ← extracted archive contents or copied executable
  Services/
    <capability-id>/       ← one per installed capability
      data/                ← persistent data
      config/              ← configuration files
      logs/                ← log files
      run/                 ← runtime state (PIDs, sockets)
        venvs/             ← Python venvs (only for python units)
          <unit-id>/       ← per-unit virtual environment
            bin/python3    ← Haven-managed interpreter
```

## Test Structure

| File | Tests | Covers |
|---|---|---|
| `HavenCoreTests.swift` | 40 | Domain models: Codable, validation, examples |
| `SpecLoaderTests.swift` | 7 | Spec loading: valid, unknown field, duplicate ID, missing ref, malformed JSON, empty dir |
| `PlannerTests.swift` | 14 | Planning: success, placeholder expansion (env/args/healthcheck), port override, directory layout, errors (missing cap/bundle/unit, required settings, cycles), topological order, default settings, template context |
| `StateTests.swift` | 29 | HavenPaths (7), ServiceDirectoryLayout (5), StoredServiceState (2), FileStateStore (15 — empty load, save/reload, upsert, remove, atomic write, thread safety) |
| `HavenExecutorTests.swift` | 37 | Install (9 — creates state, correct unit IDs, creates directories, calls bootstrap for each unit, installed status, port assignments, already-installed throws, invalid capability throws, persists resolved settings), Uninstall (6 — removes state, calls bootout for each unit, removes service directory, stops before unloading, not-installed throws, reverses dependency order), Start/Stop (6 — start calls launchd for each unit, updates to running, not-installed throws, stop reverses order, updates to stopped), Status (3 — returns unit statuses, not-installed throws, queries launchd for each unit), End-to-End (1 — full lifecycle), Artifact (6 — copies executables, deterministic paths, missing artifact throws, uninstall removes artifacts, calls bootstrap, full lifecycle with artifacts), Python (3 — rejects cleanly, does not create state, does not call launchd), ExecutorError (3 — equality, inequality, no tooling leaks) |
| `HavenCLITests.swift` | 20 | Install (8 — required arg, parsed ID, specsDir default/override, set single/multiple, baseDir default/override), Uninstall (2), Start (2), Stop (2), Status (2), List (2 — no args, baseDir override), Havenctl (2 — subcommands, default subcommand) |
| `RuntimeAdapterTests.swift` | 26 | Registry (7 — lookup, default adapters, supported types, empty registry, unsupported type, convenience prepare), NativeAdapter (7 — type, success, dependencies, empty source/args, deterministic paths, teardown), PythonAdapter (7 — type, success, venv paths, empty source/args, PATH isolation, teardown), PreparedRuntime (2 — equality), RuntimeAdapterError (3 — equality, no tooling leaks) |
| `LaunchdJobTests.swift` | 34 | LaunchdLabel (5 — prefix, generation, determinism, uniqueness), LaunchdKeepAlivePolicy (5 — plist values, shouldInclude, equality), LaunchdJob native (4 — make, log paths, env passthrough, custom keepAlive), LaunchdJob python (2 — make, log paths), Plist encoding (12 — required keys, label, args, runAtLoad, empty/nonempty env, keepAlive variants, XML validity, round-trip, env round-trip), Equality (2), LogPath (4 — stdout, stderr, under logs, deterministic) |
| `LaunchdControllerTests.swift` | 50 | LaunchdPaths (7 — default dir, custom dir, plist path, determinism, uniqueness, extension, equality), LaunchdJobStatus (6 — running/stopped/installed/notFound, equality/inequality), LaunchdControllerError (3 — equality, inequality, no tooling leaks), LaunchctlResult (3 — succeeded, failed, equality), Install (5 — writes plist, valid plist content, calls bootstrap, bootstrap failure, client throws), Uninstall (4 — calls bootout, removes plist, tolerates missing plist, bootout failure), Start/Stop (6 — calls client, failure cases, client throws), Status (6 — running, stopped, installed when plist exists, notFound, calls print, client throws), Status parsing (6 — running with PID, stopped, PID overrides state, empty output, whitespace, label preserved), Integration (2 — install-then-uninstall, creates directory), ProcessLaunchctlClient (2 — domain target, service target) |
| `ArtifactInstallerTests.swift` | 41 | ArtifactSource (6 — local, remote, string init http/https/local, equality), ArtifactFormat (4 — detect zip, tar.gz, unknown, equality), ArtifactDescriptor (2 — properties, equality), ArtifactInstallResult (2 — properties, equality), ArtifactInstallerError (3 — equality, inequality, no tooling leaks), ArtifactCache (8 — install dir, not cached, cached after content, empty dir not cached, remove, remove nonexistent, prepare clean removes existing, deterministic), Installer executable (2 — local executable, not found error), Installer archive (3 — zip, tar.gz, extraction failure cleanup), Installer cache (2 — cache hit avoids extraction, uninstall removes), Installer download (2 — remote URL, download failure error), Installer paths (2 — deterministic directory, HavenPaths convenience init), HavenPaths installed (2 — directory path, in top-level), ProcessArchiveExtractor (3 — real zip, real tar.gz, invalid archive error) |

**Total: 295 tests, all passing.**

Test fixtures use a synthetic `test-library` capability (not real third-party apps):
- Capability: `haven.capability.test-library`
- Bundle: `haven.bundle.test-library-basic` (3 runtime units, settings: `data_path` + `port`)
- Runtime units: `haven.unit.test-db` (no deps) → `haven.unit.test-worker` (depends on db) → `haven.unit.test-web` (depends on worker, port 8080)

## Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) 1.3+ — CLI only

## What Does Not Exist Yet

- No actual venv creation or package installation (adapters compute paths but don't touch filesystem)
- No Python runtime support in the executor (rejected with `.unsupportedRuntime` — adapters exist but executor blocks Python units)
- No UI
- No networking (URLSessionDownloadClient exists but no orchestration layer uses it yet)
- No update/upgrade support (must uninstall and reinstall)
- No rollback on partial install failure
