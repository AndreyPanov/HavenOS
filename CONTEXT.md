# Haven — Project Context

## What Haven Is

Haven is a macOS-first service management system. It lets users install, configure, start, stop, and monitor self-hosted services on their Mac — without ever needing to understand the underlying tooling, runtimes, or system plumbing.

**Target:** macOS 13+, Swift 5.9+, Swift Package Manager.

## Core Abstraction Chain

```
Capability → Bundle → RuntimeUnit
```

- **Capability** — a user-facing feature ("Test Library", "DNS Resolver"). Identified by reverse-DNS ID. This is what users see and choose.
- **Bundle** — a deployable implementation of one or more capabilities. Groups settings and references to runtime units.
- **RuntimeUnit** — a single launchable process (binary, container, or script). Owns lifecycle, port, healthcheck, dependencies.

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

## Module Map

| Module | Path | Purpose |
|---|---|---|
| `HavenCore` | `Sources/HavenCore/` | Domain models, specs, planning, state — no I/O beyond file state |
| `HavenCLIKit` | `Sources/HavenCLIKit/` | CLI command definitions (ArgumentParser), importable by tests |
| `HavenCLI` | `Sources/HavenCLI/` | Thin executable entry point (`havenctl`) |
| `HavenLaunchd` | `Sources/HavenLaunchd/` | launchd / ServiceManagement integration *(stub)* |
| `HavenRuntimes` | `Sources/HavenRuntimes/` | Runtime adapter protocol + built-in adapters *(stub)* |

## HavenCore Internal Structure

### Domain (`Sources/HavenCore/Domain/`)

Pure value types with Codable, Equatable, Sendable, validation, and static examples.

| File | Type | Notes |
|---|---|---|
| `Capability.swift` | `Capability` | ID, name, version, summary. Example: `.testLibraryExample` |
| `Bundle.swift` | `Bundle` | ID, name, capabilityIDs, runtimeUnitIDs, settings. Custom `init(from:)` for optional fields. Example: `.testLibraryBasicExample` |
| `RuntimeUnit.swift` | `RuntimeUnit` | ID, bundleID, runtimeType (binary/container/script), installSource, launchArguments, healthcheck, dependsOn, port, environment. Custom `init(from:)`. Examples: `.testDBExample`, `.testWorkerExample`, `.testWebExample` |
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
| `HavenPaths.swift` | `HavenPaths` | Resolves all paths from a base URL: `State/`, `Downloads/`, `Services/`, `State/services.json` |
| `ServiceDirectoryLayout.swift` | `ServiceDirectoryLayout` | Codable value type for `Services/<cap-id>/{data,config,logs,run}` |
| `ServiceStatus.swift` | `ServiceStatus` | Enum: installed, running, stopped, failed |
| `StoredServiceState.swift` | `StoredServiceState` | capabilityID, bundleID, installedAt, updatedAt, status, resolvedSettings, portAssignments, runtimeUnitIDs, directoryLayout |
| `StoredPortAssignment.swift` | `StoredPortAssignment` | unitID + port |
| `HavenState.swift` | `HavenState` | Top-level container: `[capabilityID: StoredServiceState]` |
| `StateStore.swift` | `StateStore` | Protocol: load, save, service(for:), upsert, remove |
| `AtomicFileWriter.swift` | `AtomicFileWriter` | Temp file + rename, creates parent dirs |
| `FileStateStore.swift` | `FileStateStore` | JSON-backed, NSLock for thread safety, ISO 8601 dates, tolerates missing file |

## Filesystem Layout

Under the Haven base directory:

```
<base>/
  State/
    services.json          ← persisted service state
  Downloads/               ← temporary download staging
  Services/
    <capability-id>/       ← one per installed capability
      data/                ← persistent data
      config/              ← configuration files
      logs/                ← log files
      run/                 ← runtime state (PIDs, sockets)
```

## Test Structure

| File | Tests | Covers |
|---|---|---|
| `HavenCoreTests.swift` | 40 | Domain models: Codable, validation, examples |
| `SpecLoaderTests.swift` | 7 | Spec loading: valid, unknown field, duplicate ID, missing ref, malformed JSON, empty dir |
| `PlannerTests.swift` | 14 | Planning: success, placeholder expansion (env/args/healthcheck), port override, directory layout, errors (missing cap/bundle/unit, required settings, cycles), topological order, default settings, template context |
| `StateTests.swift` | 29 | HavenPaths (7), ServiceDirectoryLayout (5), StoredServiceState (2), FileStateStore (15 — empty load, save/reload, upsert, remove, atomic write, thread safety) |
| `HavenCLITests.swift` | 3 | CLI flag parsing |

**Total: 90 tests, all passing.**

Test fixtures use a synthetic `test-library` capability (not real third-party apps):
- Capability: `haven.capability.test-library`
- Bundle: `haven.bundle.test-library-basic` (3 runtime units, settings: `data_path` + `port`)
- Runtime units: `haven.unit.test-db` (no deps) → `haven.unit.test-worker` (depends on db) → `haven.unit.test-web` (depends on worker, port 8080)

## Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) 1.3+ — CLI only

## What Does Not Exist Yet

- No install/download execution logic
- No process execution or lifecycle management
- No launchd integration (stub module exists)
- No runtime adapters (stub module exists)
- No UI
- No networking
