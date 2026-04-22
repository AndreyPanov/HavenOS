🧭 HavenOS — MVP+ Roadmap (Service Platform Evolution)

🎯 Vision

Haven turns a fresh Mac mini into a personal cloud with one-click service installs.

Haven abstracts:
	•	installation complexity
	•	runtime orchestration
	•	system dependencies

Into:

Add → Start → Use (inside Haven)

⸻

🧱 Current State

✅ What works
	•	Spec-driven system (Capability → Bundle → RuntimeUnit)
	•	Native runtime execution
	•	Artifact copying (GitHub Release + direct-url, zip/tar.gz/tar.xz)
	•	launchd lifecycle management (load/unload, ThrottleInterval patching)
	•	Deterministic execution model
	•	Python runtime support (venv, pip install, pinned versions)
	•	Install DSL with 8 step actions + rollback (InstallStepExecutor)
	•	Dependency model (spec-level, not yet runtime-validated)
	•	Storage policies on Bundle (persistent, userVisible)
	•	Directory roles with template expansion
	•	Settings model (string/integer/boolean/path)
	•	Healthcheck model (http/tcp/exec)
	•	Onboarding system (info/credentials/action steps with fields + URL)
	•	Provisions (download sample data at install)
	•	Secret generation (generateSecret → template injection)
	•	URL-based icons and screenshots (AsyncImage in GUI)
	•	Rich service metadata (fullDescription, iconImage, screenshots)
	•	Navidrome pilot spec validated through full pipeline

⚠️ Remaining Limitations
	•	~~No runtime dependency validation~~ ✅ Resolved (DependencyValidator)
	•	~~No multi-service composition~~ ✅ Resolved (readiness probes, shared env/dirs)
	•	Pilot services not yet tested with live installs (spec-only so far)

✅ Recently Fixed
	•	launchd restart delay: switched to load/unload (legacy but reliable), auto-patches existing plists with ThrottleInterval=1
	•	launchd bootstrap error 5: avoided by using legacy load instead of modern bootstrap after unload
	•	Home tab service reordering: sorted by capability ID
	•	Service detail view not updating on stop/start: uses live lookup by ID instead of snapshot
	•	Card button navigation conflict: header navigates via onTapGesture, action buttons independent
	•	Working directory for .NET apps: install dir as working dir (wwwroot/ access)
	•	URL-based icons/screenshots: AsyncImage in ServiceIconView and DiscoveryDetailView
	•	Discovery detail page: full lifecycle controls (start/stop/restart/open/remove) after install
	•	Remove button → "Stop & Remove" to clarify auto-stop behavior
	•	Onboarding steps: "Open in Browser" instead of raw localhost URLs
	•	Discovery header: live status via installedService instead of static plugin.isInstalled
	•	ifNotExists guard on install steps: safe reinstalls without overwriting config/secrets

⸻

🚀 Strategic Goal

Enable Haven to:

Convert chaotic open-source install instructions into deterministic JSON specs

⸻

🗺️ Roadmap Overview

Phase	Focus	Outcome	Status
1	Spec Foundation	Express real services in JSON	✅ DONE
2	Install Engine	Execute real installs	✅ DONE
3	Dependencies	Support helper tools	✅ DONE
4	Storage Model	Support content-based apps	✅ DONE
5	Onboarding UX	Make services usable	✅ DONE
6	Templates	Scale service creation	⬜ Not started
7	Pilot Services	Validate system	🔶 Navidrome spec done, live test pending
8	Multi-Service	Unlock complex apps	✅ DONE
9	Facade Layer	Stable abstraction between UI and backends	✅ DONE
10	Domain Models	Backend-independent capability models	✅ DONE
11	Native UI	Haven-native capability screens	✅ DONE (merged with 12)
12	Books (Kavita)	First full facade + native UI capability	✅ DONE
13	Replaceability	Validate backend swap	✅ DONE
14	Files	Second capability	⬜ Not started


⸻

🧩 Phase 1 — Spec Foundation ✅ COMPLETE

All deliverables implemented and tested:
	•	RuntimeUnit: `install`, `directories`, `dependencies` fields
	•	Bundle: `storage` policies, `onboarding`, `provisions`
	•	Directory roles with template expansion (`${role_dir}`)
	•	Settings model (SettingField: string/integer/boolean/path)
	•	Healthcheck model (http/tcp/exec with interval + retries)
	•	Artifact types: github-release, direct-url; formats: zip, tar.gz, tar.xz
	•	StrictJSONDecoder validates all nested blocks
	•	Full backward compatibility (all existing tests pass unchanged)

⸻

⚙️ Phase 2 — Install Engine (DSL) ✅ COMPLETE

All deliverables implemented and tested:
	•	InstallStepExecutor: runs InstallBlock steps with automatic rollback
	•	8 step actions: mkdir, copy, move, chmod, writeFile, symlink, generateSecret, cleanup
	•	Path safety: all paths validated inside service root, traversal rejected
	•	Rollback: completed steps reversed on failure (file restore, move undo, permission restore)
	•	Secret generation: crypto-random bytes (hex/base64) injected into template context
	•	Integrated into HavenExecutor between artifact install and runtime preparation
	•	23 unit tests for all actions, rollback, path safety, template expansion
	•	Navidrome pilot spec validates full pipeline (spec → plan → expanded install steps)

⸻

🔌 Phase 3 — Dependencies ✅ COMPLETE

All deliverables implemented and tested:
	•	Dependency type: id, kind (helperBinary/library), required, validateCommand, description
	•	DependencyValidator: deterministic absolute-path binary discovery (no $PATH)
	•	Search paths: /opt/homebrew/bin → /usr/local/bin → /usr/bin
	•	Injectable commandRunner for testing; validates via validateCommand when provided
	•	Integrated into HavenExecutor.install() after planning, before side effects
	•	Required missing deps block install; optional deps warn only
	•	Consumer-facing errors never expose tooling details
	•	10 unit tests covering discovery, dedup, libraries, mixed deps
	•	Navidrome spec declares optional ffmpeg dependency with absolute-path validate

⬜ Remaining:
	•	Calibre-Web spec: express ImageMagick dependency

⸻

💾 Phase 4 — Storage Model ✅ COMPLETE

All deliverables implemented:
	•	StoragePolicy on Bundle: persistent + userVisible per directory role
	•	Directory roles on RuntimeUnit: maps role → relative path or template expression
	•	Planner resolves directories into `${role_dir}` template variables
	•	User-visible content directories can map to user settings (e.g. `${music_path}`)
	•	Navidrome spec demonstrates full storage model (5 roles with policies)

⸻

🧭 Phase 5 — Onboarding System ✅ COMPLETE

All deliverables implemented:
	•	Onboarding spec: steps with type (info/credentials/action), title, body, fields, url
	•	OnboardingField: label + value pairs with template expansion
	•	Planner expands all templates in onboarding steps
	•	PostInstallSheet in GUI renders onboarding steps
	•	Navidrome demonstrates 4-step consumer onboarding:
	  1. “Your music server is ready” (reassurance)
	  2. “Point it to your music” (folder field)
	  3. “Create your account” (Open button)
	  4. “Listen anywhere” (server address field)

⸻

🧩 Phase 6 — Service Templates

🎯 Goal

Scale service creation.

⸻

🔧 Deliverables

Templates:
	•	single-binary-web-app
	•	archive-based-service
	•	library-server
	•	python-web-app
	•	app-with-helper

⸻

✅ Acceptance Criteria
	•	New service spec < 30 minutes to create
	•	Minimal duplication across services

⸻

🧪 Phase 7 — Pilot Services 🔶 IN PROGRESS

🧩 Target Services

1. File Browser (MVP baseline) ✅ SPEC COMPLETE
	•	Full 3-file spec (capability, bundle, runtimes) — minimal baseline template
	•	GitHub Release artifact, 2 install steps (mkdir only), 2 directory roles
	•	No dependencies, no config files, no secrets — all config via CLI flags
	•	HTTP healthcheck (/health), 3-step consumer onboarding
	•	8 end-to-end tests (SpecLoader → Planner pipeline)
	•	⬜ Live install test pending

⸻

2. Navidrome (music) ✅ SPEC COMPLETE
	•	Full 3-file spec (capability, bundle, runtimes) with all schema features
	•	GitHub Release artifact (v0.61.2), 8 install steps, 5 directory roles
	•	Optional ffmpeg dependency, HTTP healthcheck
	•	4-step consumer onboarding
	•	8 end-to-end tests (SpecLoader → Planner pipeline)
	•	🔶 Live install tested — uncovered and fixed: tilde expansion, HTTP validation, external paths

⸻

3. Kavita (books) ✅ SPEC COMPLETE + LIVE TESTED
	•	Full 3-file spec (capability, bundle, runtimes) — library-server pattern
	•	GitHub Release artifact (v0.8.9.1), 5 install steps (mkdir, generateSecret, writeFile, chmod)
	•	Config generation: JWT token + appsettings.json with template expansion
	•	Archive stripFirstDirectory with name collision handling
	•	2 directory roles (config, content), HTTP healthcheck (/api/health)
	•	3-step consumer onboarding, port 5001 (avoids macOS AirPlay on 5000)
	•	8 end-to-end tests (SpecLoader → Planner pipeline)
	•	Live install validated — uncovered and fixed:
	  - Port 5000 conflict with macOS AirPlay Receiver
	  - Working directory must be install dir for .NET apps (wwwroot/)
	  - Directory symlinks: install dir roles → service root for config access
	  - stripFirstDirectory name collision (Kavita/Kavita)
	  - Native adapter must allow zero launch arguments

⸻

4. Calibre-Web (advanced) ✅ SPEC COMPLETE
	•	Full 3-file spec (capability, bundle, runtimes) — first Python runtime pilot
	•	Python runtime: calibreweb==0.6.26, entrypoint module, venv-managed
	•	4 directory roles (config, data, logs, content maps to ${library_path})
	•	3 install steps (mkdir × 3), 2 optional dependencies (ebook-convert, ImageMagick)
	•	Storage policies: config + data persistent, content user-visible
	•	3-step onboarding: info → credentials → action (open + set library path)
	•	8 end-to-end tests (SpecLoader → Planner pipeline)
	•	⬜ Live install test pending

	Missing Haven features exposed:
	•	No port flag injection for Python apps (calibreweb doesn't accept --port;
	  port is set in app.db after first launch — requires post-start configuration)
	•	No conditional provisions in schema v2 (old spec had use_sample_library gate,
	  but Provision.condition is not validated in current Planner)
	•	No post-start hooks (setting library path requires opening the admin UI manually)
	•	Dependency discovery doesn't handle ebook-convert (lives in Calibre.app bundle,
	  not in standard /opt/homebrew/bin paths)

⸻

✅ Acceptance Criteria
	•	All 4 services install via Haven
	•	No manual steps outside Haven
	•	No exposed system tooling

⸻

🔗 Phase 8 — Multi-Service Composition ✅ COMPLETE

All deliverables implemented and tested:
	•	ReadinessProbe on RuntimeUnit: TCP/HTTP/exec with timeout + interval
	  - Polled during startup to ensure dependencies accept connections before launching dependents
	  - Timeout → rollback: already-started units stopped automatically
	•	sharedDirectories on Bundle: dirs visible to all units as ${shared_<role>_dir}
	•	sharedEnvironment on Bundle: env vars injected into every unit (unit-level wins on conflict)
	•	ReadinessChecker: TCP connect, HTTP GET, or shell exec polling
	•	start() is now async with rollback; startSync() preserved for CLI
	•	Planner two-pass: plan all units, then expand sharedEnv using service-level context
	•	Readiness probes persisted in StoredServiceState for restart
	•	Topological sort (already existed) ensures correct startup/shutdown order
	•	Gitea pilot spec (app + PostgreSQL): 12 end-to-end tests validate full pipeline

Complexity kept minimal:
	•	3 new optional fields total (readinessProbe, sharedDirectories, sharedEnvironment)
	•	Single-unit bundles see zero change — all fields default to empty/nil
	•	No container isolation, no service mesh, no resource limits
	•	Haven manages processes on a shared filesystem, not sandboxes

⸻

🧠 Guiding Principles

1. No Tooling Exposure

User must never see:
	•	Homebrew
	•	Python
	•	Docker
	•	PATH

⸻

2. Deterministic Runtime
	•	absolute paths only
	•	no implicit environment
	•	no system assumptions

⸻

3. Atomic Install
	•	all or nothing
	•	no partial state
	•	rollback guaranteed

⸻

4. Spec-Driven Everything
	•	no hardcoded services
	•	no special cases

⸻

📦 Definition of Done (MVP+)

Haven can:

✅ Install real OSS services from upstream
✅ Manage lifecycle reliably
✅ Provide usable UX without docs
✅ Support content-based apps (files/music/books)
✅ Hide all infrastructure complexity

⸻

🔥 Critical Success Metric

A non-technical user installs a service and uses it in < 2 minutes.

⸻

🔄 Future: Service Version Update Mechanism

Built-in service specs currently hardcode artifact versions (e.g. Kavita v0.8.9.1).
This must not stay hardcoded. A future phase should implement:

	•	Version discovery: query upstream (GitHub Releases API) for the latest stable version
	•	Update check: compare installed version against latest available
	•	Update flow: download new artifact, re-run install steps, restart service
	•	Data safety: preserve config/data directories across updates (storage policies already support this)
	•	UI: surface available updates in the Home and Detail views

This unblocks Haven from being a one-shot installer and makes it a proper service manager.

⸻

🧭 Immediate Next Steps (Concrete)
	1.	Live install test: File Browser via GUI (simplest end-to-end)
	2.	Complete Navidrome live install (verify HTTP reachability after fixes)
	3.	Live install test: Calibre-Web (first Python runtime end-to-end)
	4.	Live multi-unit test: Gitea + PostgreSQL (first multi-unit end-to-end)
	5.	Address missing features: port injection, post-start hooks, Calibre.app dep discovery

⸻
UPDATED 21.04.26 (UI redesign, navigation overhaul)

🧭 HavenOS — Extended Roadmap (Facade + Native Capabilities)

⸻

🧩 Phase 9 — Facade Layer Foundation ✅ COMPLETE

All deliverables implemented:
	•	CapabilityFacade protocol (@MainActor, Observable) with state, health, actions, advancedURL
	•	CapabilityState (idle/starting/ready/degraded/error), CapabilityHealth, CapabilityAction
	•	BackendAdapter protocol (Sendable) for engine abstraction
	•	AdapterRegistry: maps capability IDs to facade factories, falls back to GenericFacade
	•	FacadeActionBar: renders actions from facade.availableActions with glass styling
	•	ServiceManager.facade(for:) creates facades on demand, caches, refreshes on state change
	•	advancedURL support with “Open in Browser” as secondary action

⸻

🧠 Phase 10 — Capability Domain Models ✅ COMPLETE

All deliverables implemented:
	•	BooksLibrary (libraryPath, scanStatus, itemCount) + BooksFacade protocol
	•	BackendSetupState (ready/needsSetup/settingUp/failed) — generic, no auth leakage
	•	FilesRoot + FilesFacade protocol
	•	MusicLibrary (libraryPath, scanStatus, artist/album/track counts) + MusicFacade protocol
	•	ScanStatus shared enum (idle/scanning/complete/error)
	•	All models in HavenFacade/Models/ — zero backend terms, pure user-facing concepts

⸻

🎨 Phase 11 — Native Capability UI Foundation ✅ COMPLETE (merged with Phase 12)

Delivered as part of the Books vertical slice:
	•	BooksHomeView: state-driven UI (stopped/starting/setup/ready) from BooksFacade protocol
	•	FacadeActionBar: reusable action buttons from facade.availableActions
	•	Navigation: HomeView routes to native screen via `any BooksFacade` protocol check
	•	StatusBadgeView, ServiceIconView, OnboardingStepsView — shared components
	•	“Open in Browser” is secondary; primary experience is inside Haven

⸻

📚 Phase 12 — First Full Capability: Books (Kavita) ✅ COMPLETE

All deliverables implemented:
	•	BooksFacade protocol: library, setupState, setLibraryPath(), rescan()
	•	KavitaBooksFacade: JWT auth, API client, auto-reconnect, series count
	•	KavitaAPIClient: login, register, getLibraries, scanAllLibraries, getSeriesCount, health
	•	BooksHomeView: state-driven (stopped → start, needsSetup → connect, ready → library info)
	•	BooksConnectSheet: chooser (Create Account / Sign In) with slide transitions
	•	KavitaSpec: native Swift spec (replaces JSON catalog files)
	•	BuiltInCatalog: always-available specs merged with disk catalog
	•	Auto-provisioning: Haven creates and manages Kavita accounts automatically
	  - Health polling: waits for Kavita API before auth (fixes connection-refused errors)
	  - Cascading auth: saved token → saved password → managed credentials → register new account
	  - Managed credentials persist separately, survive custom account switching
	  - Settings toggle: "Account managed by Haven" ON/OFF with seamless switching
	•	Consumer-focused UX:
	  - Auto-start after install (no manual start needed)
	  - No stop/restart buttons (Haven manages lifecycle internally)
	  - Download progress % shown during artifact installation
	  - API error parsing: ASP.NET validation, plain text, JSON objects/arrays
	  - 27 tests for auth state machine and error parsing
	•	Architectural boundaries enforced:
	  - UI uses `any BooksFacade` — never references KavitaBooksFacade
	  - Auth (connect/disconnect) lives on concrete class, not protocol
	  - BackendSetupState abstracts auth without leaking it
	  - Swap backend → zero UI changes needed (setupState == .ready skips auth)

⸻

🔁 Phase 13 — Backend Replaceability ✅ COMPLETE

All deliverables implemented:
	•	FacadeLifecycle: shared helper eliminates duplicated ServiceManager delegation across all facades
	•	MockBooksFacade: second Books backend with API key auth (not username/password)
	  - Validates that BackendSetupState abstracts different auth mechanisms
	  - Uses FacadeLifecycle for lifecycle actions, same as KavitaBooksFacade
	  - Mock library data (42 items), simulated rescan with delay
	  - API key persisted in UserDefaults, auto-reconnect on refresh
	•	MockBooksSetupSheet: API key entry UI (concrete MockBooksFacade, not protocol)
	•	BooksHomeView handles multiple backends:
	  - Setup sheet: downcasts to KavitaBooksFacade or MockBooksFacade for backend-specific UI
	  - Disconnect: backend-specific disconnect in ready view
	  - All protocol-level state (setupState, library, actions) works identically
	•	AdapterRegistry: swap one line to switch Kavita → Mock backend
	•	GenericFacade, KavitaBooksFacade, MockBooksFacade all use FacadeLifecycle — zero duplication
	•	Acceptance criteria met:
	  - Mock backend runs with alternative adapter (API key auth)
	  - Zero protocol-level UI changes needed — only backend-specific sheets differ
	  - Migration path: swap AdapterRegistry registration, same capability ID

⸻

🎨 UI Redesign — App Navigation ✅ COMPLETE

All deliverables implemented:
	•	Sidebar restructured: Home + dynamic capability tabs + Settings
	  - Discovery removed as separate tab; Home now serves as capability catalog
	  - Installed capabilities with native UI get their own sidebar tab (e.g. "Books")
	  - Tabs animate in on install, auto-navigate to the new capability
	•	Home tab: overview of all capabilities (added and available)
	  - Live status indicators: green "Online", gray "Offline", red "Error"
	  - "Add" button for uninstalled capabilities (renamed from "Install")
	  - Cards link to detail view for capability info before adding
	•	Capability tabs: dedicated management screens
	  - Books tab: "Books Library" title, "powered by Kavita" subtitle
	  - Setup, connect, manage — all inside Haven, not in browser
	•	Naming: "Install" → "Add" across all UI surfaces
	•	DiscoveryCardView renamed to CapabilityCardView

⸻

🚀 Phase 14 — Second Capability (Files)

🎯 Goal

Generalize system beyond Books

⸻

🔧 Deliverables

FilesFacade

* root management
* file listing
* basic actions

FileBrowserAdapter

* config mapping
* CLI/start control

Files UI

* native file browsing
* folder selection
* preview (optional later)

⸻

✅ Acceptance Criteria

* Same UI patterns reused
* No service-specific UI leaks
* Facade abstraction holds

⸻

🧠 Updated Strategic Direction

After these phases, Haven becomes:

NOT:

* service launcher
* self-hosting UI
* homelab dashboard

BUT:

A native operating layer for personal data services

⸻

🔥 Critical Evolution (What changed)

Your original roadmap ends at:

“Install → Start → Open”  ￼

Your new roadmap extends it to:

Install → Start → Use (inside Haven)

That’s the transformation.

⸻

🧭 Suggested Execution Order (Practical)

Do NOT follow phases strictly linearly.

Instead:

1. Phase 9 (Facade skeleton)
2. Phase 11 (UI shell minimal)
3. Phase 12 (Books full vertical slice)
4. Backfill Phase 10 (refine models)
5. Phase 13 (replaceability validation)
6. Phase 14 (Files)

👉 Think vertical slice first, then generalize

⸻

💬 Final Note

This extension turns Haven from:

“infrastructure abstraction”

into:

product abstraction

And the key enabler is exactly what you identified:

Facade = stability + replaceability + UX control

⸻
