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
	•	Dependency model with runtime validation and optional auto-install artifacts
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
12.5	Books Usability	Device access, auto-organize, scan errors	✅ DONE
13	Replaceability	Validate backend swap	✅ DONE
14	Music (Navidrome)	Second capability — validate pattern scales	✅ DONE
14.5	Platform Hardening	Shared protocols, zero downcasts, lifecycle tests	✅ DONE
15	Movies (Jellyfin)	Third capability — video streaming	✅ DONE
16	Backup & Sync	Trust milestone — capability-aware backup	✅ DONE
17	Consistency	Unified setup, folder, and UI patterns	🔄 Shared components remaining
18	Service Updates	Version discovery + safe atomic updates	✅ DONE
19	Haven App Updates	Sparkle-based app update path	✅ DONE
20	macOS Topbar Menu	Always-present menu bar control surface	✅ DONE
21	Files	Basic file access capability	🔄 ACTIVE
22	Credential Convenience & Passwords Bridge	Prompt-free local credentials + simpler cross-device login	✅ DONE


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


🧭 HavenOS — Roadmap Update 22.04.26 (Books Usability Layer)

⸻

📚 Phase 12.5 — Books Usability (Local Files + Device Access) ✅ COMPLETE

All deliverables implemented:

1. Device Access (OPDS-first, credential-free)
	•	DeviceAccessSection: OPDS feed URL with API key baked in (no login on device)
	•	Copy-to-clipboard with checkmark feedback
	•	QR code popover (CoreImage CIQRCodeGenerator) for scanning from e-reader/phone
	•	Reader app guides: Kobo/Kindle (KOReader), iOS (Panels/KyBook), Android (Moon+/Librera), Comics (Mihon/Chunky)
	•	serverAddress + opdsURL computed from hostname + port + apiKey

2. Library Organization (Transparent)
	•	LibraryOrganizer: auto-moves loose book files into subdirectories before scan
	  - Kavita requires `Books/Title/file.epub` structure — users just drop files in
	  - Supports epub, pdf, cbz, cbr, cb7, cbt, zip, rar, 7z
	  - Skips hidden files, handles unicode/CJK filenames
	  - 14 unit tests (organization, edge cases, extensions, case-insensitive)
	•	Folder structure hint in library info section explains the pattern

3. Rescan UX
	•	Auto-rescan on connect: organizes files and triggers scan on every app launch
	•	Auto-rescan after “Add Books”: sets pendingRescanOnFocus flag, rescans on NSApplication.didBecomeActiveNotification
	•	Inline “Refresh Library” button next to “Add Books” for manual rescan
	•	Scan completion detection via lastScanned timestamp polling (not item count)
	•	Scanning banner with progress indicator shown during scan

4. Scan Error Reporting
	•	KavitaLogParser: parses Kavita log files after scan for “Unable to parse” errors
	•	Shows warning: “N files couldn’t be imported” with expandable list of file names
	•	Errors cleared on each new scan, populated when scan completes

5. Scanner Safety (fileGroupTypes fix)
	•	Auto-fix: removes unsafe fileGroupTypes values (0, 1, 5) that crash macOS .NET scanner
	•	Safe values [2, 3, 4] (epub, PDF, images) enforced on every connect
	•	createLibrary uses safe values by default
	•	5 unit tests for fileGroupTypes safety

6. Library Folder Management
	•	"Change" button next to library path opens NSOpenPanel folder picker
	•	Updates Kavita library folders via API, persists path override in UserDefaults
	•	Auto-creates folder if needed, triggers rescan after change
	•	Path resolution: UserDefaults override > StoredServiceState > default ~/Books

7. Clean Ready Screen
	•	Library info: path + change button, item count, Add Books + Check for New Books buttons
	•	Scan errors section (when applicable)
	•	Device access: OPDS URL, copy, QR code, reader guides
	•	Signed-in user info (custom accounts only)
	•	Improved text visibility (.secondary/.tertiary instead of .tertiary/.quaternary)

Phase 12 = “Books capability foundation”
Phase 12.5 = “Books usable in real life”

⸻

🔥 One-liner

Phase 12.5 turns Books from “installed software” into a personal cloud library

⸻

🎵 Phase 14 — Music (Navidrome) ✅ COMPLETE

All deliverables implemented:

1. MusicFacade (Domain Layer)
	•	MusicLibrary: libraryPath, artistCount, albumCount, trackCount, scanStatus
	•	MusicFacade protocol: setLibraryPath(), rescan()
	•	NavidromeMusicFacade: full Subsonic/REST API integration

2. NavidromeAdapter (Backend Layer)
	•	NavidromeAPIClient: login, createAdmin, getLibraryInfo, startScan, getScanStatus, isHealthy
	•	Subsonic API auth: salt + MD5 token per-request
	•	Auto-connect: health polling → saved token → saved password → managed credentials → create admin
	•	Auto-connect exhaustion: shows error with Retry + manual Sign In
	•	NavidromeSpec: built-in Swift spec (matches KavitaSpec pattern)

3. Music UI (State-driven)
	•	MusicHomeView: stopped → starting → needsSetup → settingUp → empty → ready → scanning → error
	•	Library card: artist/album/track counts, folder path, Add Music + Check for New Music buttons
	•	AccountInfoSection: shared "Signed in as" component (used by both Books and Music)
	•	MusicConnectSheet: three-mode chooser (choose → create account / sign in)

4. Auth & Account Management
	•	Managed mode: Haven auto-creates and manages Navidrome admin account
	•	Custom mode: user signs in manually, Haven stores credentials
	•	Settings integration: "Music Library" section with managed toggle + sign-in
	•	Seamless switching between managed and custom modes

5. Rescan UX
	•	Auto-rescan on connect
	•	"Check for New Music" button (inline + toolbar menu)
	•	Scan status polling with completion detection
	•	Scanning banner with progress indicator
	•	pendingRescanOnFocus: rescan when app regains focus after adding files

6. Device Access (Subsonic credentials)
	•	"Listen on your devices" section with server address, username, and password
	•	Per-field copy buttons with independent feedback
	•	QR code for server address
	•	Password visibility toggle (hidden by default)
	•	Client guides: iPhone (Amperfy/Substreamer), Android (Symfonium/DSub), Desktop (browser/Sonixd)
	•	Note: Subsonic requires manual credential entry (no token-in-URL like OPDS)

7. Open in Browser (Fallback)
	•	Navidrome web UI as secondary action in toolbar menu
	•	Sign Out option for custom accounts

8. Shared Components Extracted
	•	AccountInfoSection: "Signed in as" + "Change in Settings" — used by both Books and Music
	•	Friendlier download progress: "Downloading…" instead of "Downloading artifact…"

⸻

⚠️ Known Limitations
	•	Music folder path is immutable after initial install (Navidrome DB constraint — library ID 1 path cannot be changed via API)
	•	Passwords app integration is not direct for local URLs; Phase 22 defines the secure local-storage and user-friendly bridge
	•	Navidrome multi-library API (POST /api/library) could enable adding folders in the future

⸻
ROADMAP - update 24.04.26

Phase 14.5 — Capability Platform Hardening ✅ COMPLETE

Goal:
Reduce duplication, enforce backend boundaries, and make the next capability cheaper to build.

Deliverables:

1. ConnectableFacade Protocol (HavenFacade)
	•	New protocol extending CapabilityFacade for capabilities that authenticate with a backend
	•	ConnectionState enum (disconnected/connecting/connected/failed) — shared, replaces per-facade duplicates
	•	DeviceAccessInfo value type: serverAddress, username, password, tokenURL — abstracts credential-based and token-based device access
	•	Full auth lifecycle: connect(), createAccount(), disconnect(), signOut(), autoConnect()
	•	Account management: isManagedByHaven, connectedUsername, switchToManaged/Custom()
	•	Auto-connect state: isAutoConnecting, autoConnectExhausted
	•	backendName, scanErrors, deviceAccessInfo — surfaced at protocol level
	•	BooksFacade and MusicFacade now extend ConnectableFacade (setupState moved up)

2. Shared ConnectSheet (HavenApp/Components)
	•	Single ConnectSheet replaces BooksConnectSheet + MusicConnectSheet (deleted)
	•	Parameterized by icon + libraryLabel — works for any ConnectableFacade
	•	Three-mode chooser (choose → create account / sign in) with slide transitions
	•	Used by BooksHomeView, MusicHomeView, and SettingsView

3. Backend Downcast Elimination
	•	BooksHomeView: all `facade as? KavitaBooksFacade` downcasts removed (was ~15 occurrences)
	•	MusicHomeView: all `facade as? NavidromeMusicFacade` downcasts removed (was ~12 occurrences)
	•	SettingsView: unified `capabilityLibrarySection()` replaces separate books/music sections
	•	Device access: views read facade.deviceAccessInfo instead of casting to concrete type
	•	Scan errors, account info, sign out — all via protocol, no downcasts

4. Backend-Neutral Copy
	•	"Navidrome indexes them automatically" → "they'll be indexed automatically"
	•	"Powered by Kavita/Navidrome" → "Powered by \(facade.backendName)"

5. ServiceManager Hardening
	•	Credential cleanup on uninstall: clears all UserDefaults keys for kavita/navidrome prefixes
	•	Facade cache eviction on uninstall (before executor call)
	•	Double-start guard: startService() is a no-op when already running
	•	defer-based flag cleanup in installService() (isPerformingAction always resets)
	•	Refresh order fix: installedServices built before facade.refresh() (prevents stale reads)

6. Auto-Connect Race Fix
	•	isAutoConnecting set before Task creation (not inside async method)
	•	Previous autoConnectTask cancelled before starting new one
	•	Both KavitaBooksFacade and NavidromeMusicFacade patched

7. ServiceManager Tests (241 lines, 7 tests)
	•	Double-start guard: no-op when running, proceeds when stopped
	•	isPerformingAction cleanup: always reset after installService (even on failure)
	•	Credential cleanup: Kavita keys, Navidrome keys, cleanup even when executor fails
	•	Facade cache: uninstall removes cached facade

Acceptance criteria — all met:
	•	BooksHomeView has zero Kavita-specific imports or type checks ✅
	•	MusicHomeView has zero Navidrome-specific imports or type checks ✅
	•	Shared ConnectSheet reused by Books, Music, and Settings ✅
	•	Backend-specific terms appear only in concrete facades ✅
	•	ServiceManager lifecycle correctness validated by tests ✅

🎬 Phase 15 — Movies (Jellyfin) ✅ COMPLETE

All deliverables implemented:

1. MoviesFacade (Domain Layer — HavenFacade)
	•	MoviesLibrary: libraryPath, movieCount, showCount, scanStatus
	•	MoviesFacade protocol extending ConnectableFacade: setLibraryPath(), rescan()
	•	SetupPhase enum: waitingForServer, creatingAccount, awaitingLibraryPath,
	  creatingLibrary, scanning, complete
	•	LibraryContentType enum (moviesAndShows default — no user choice needed)

2. JellyfinAPIClient (Backend Layer)
	•	Auth: initial setup wizard API (multi-step), login
	•	Libraries: createLibrary, removeLibrary, getLibraries, refreshLibrary, getItemCounts
	•	Scheduled tasks: getScheduledTasks (scan progress)
	•	Health: /System/Ping (returns plain text)
	•	X-Emby-Token header auth (not Bearer)
	•	CRITICAL: PathInfos must be inside LibraryOptions in createLibrary POST body
	•	All methods async/throws, Sendable struct

3. JellyfinMoviesFacade (Concrete Facade)
	•	Implements MoviesFacade + ConnectableFacade
	•	Setup wizard flow:
	  - Health poll → isSetupComplete check → run Jellyfin wizard API → await folder → scan
	  - Always creates single "mixed" collection type (movies + shows together)
	  - Removes all existing libraries before creating new one (prevents duplicates)
	  - Skip wizard on restart: checks for saved managed credentials before querying API
	•	Post-setup: standard auto-connect (token → password → managed creds)
	•	Scan polling: count-stability based (3 consecutive same counts = done)
	  - Not task-based — Jellyfin processes metadata in background after task completes
	•	Credential persistence: haven.jellyfin.* UserDefaults keys

4. JellyfinSpec (Built-in Catalog)
	•	Capability: haven.capability.jellyfin, v10.10.6, port 8096
	•	Artifact: GitHub Release tar.gz (macOS arm64 + x64), stripFirstDirectory
	•	5 install steps (mkdir only), optional ffmpeg dependency with auto-install
	  - jellyfin-ffmpeg v7.1.3-5 from GitHub, direct-url tar.xz
	  - Ad-hoc code signing for extracted Mach-O files (Gatekeeper)
	•	Directories: data, config, cache, logs, content (→ movies_path)
	•	Healthcheck: HTTP GET /System/Ping

5. Movies UI — Inline Setup Wizard
	•	MoviesHomeView: state-driven with progressive inline form
	  - Steps appear as cards, completed steps collapse to checkmarks
	  - Auto steps (server ready, account created) complete without user input
	  - User step: folder picker only (content type removed — always mixed)
	  - Scan step shows progress, transitions to ready view on completion
	  - User makes exactly 1 decision (folder) to go from install to streaming

6. Device Access
	•	MoviesDeviceAccessSection: server address + credentials
	•	VLC/Infuse recommended, plus Jellyfin app, Swiftfin, Findroid, browser
	•	Per-field copy buttons, QR code, password visibility toggle
	•	Collapsible "How to watch" guide section

7. Open in Browser
	•	Jellyfin web UI as secondary action in toolbar menu
	•	Sign Out option for custom accounts

⸻

⚠️ Lessons Learned
	•	PathInfos JSON placement: must be inside LibraryOptions, not top-level (caused empty library paths)
	•	Mixed collection type: separate movies + tvshows libraries on same folder causes TV scanner to claim movie files
	•	Scan polling: Jellyfin's scheduled task finishes quickly (file discovery), but metadata downloads continue in background — poll item counts until stable
	•	Duplicate libraries: repeated installs created Movies, Movies2, etc. — must remove existing before creating new
	•	Wizard on restart: /Startup/Configuration endpoint may still return 200 after setup — check saved credentials first

⸻

✅ Acceptance Criteria — All Met
	•	User adds movies folder, sees metadata populate, can stream to TV/phone ✅
	•	No manual backend setup required ✅
	•	Setup wizard completes with 1 user decision (folder) ✅
	•	Zero Jellyfin-specific terms in MoviesHomeView ✅
	•	28 tests for facade state machine, API error parsing, setup phase transitions ✅

⸻

💾 Phase 16 — Backup & Sync System

🎯 Goal

Move Haven from "local services manager" to "trusted personal cloud."

Answer the most important long-term user question:

"If my Mac mini dies, do I lose everything?"

→ No — your data, settings, and service state are protected automatically.

This is a capability-aware backup system designed specifically for Haven.

Think: Time Machine for your personal cloud — not a manual sysadmin backup workflow.

⸻

🔧 Deliverables

1. Backup Settings UI
	•	Dedicated Backup section in Settings
	•	Backup destination via macOS-native folder picker only
	•	Supported: External Drive, NAS Folder, Mounted Network Share (SMB/NFS), Custom Path
	•	No terminal setup, no manual scripting

2. Per-Capability Backup Mapping
	•	User sees backup by capability, not by system folders
	•	Example: Books → /Backups/Books, Music → /Backups/Music, Movies → /Backups/Movies
	•	Each capability section appears only when that capability is installed — no empty/placeholder rows
	•	Haven manages the real filesystem details internally

3. Backup Schedule
	•	Options: Daily, Every 3 Days, Weekly, Manual Only
	•	Future extension: backup after major changes (large scan, new import, config changes)

4. Capability-Aware Backup Scope
	•	BACK UP: user content (books, music, movies, smart home configs), service state (config files, managed credentials, metadata databases, indexes, library state, user preferences, automation settings)
	•	DO NOT BACK UP: binaries, downloaded artifacts, temporary caches, generated runtime files, re-installable dependencies — those are recreated automatically
	•	This is the core product differentiator

5. Backup Health Visibility
	•	Clear backup status always visible: last backup date, status (Healthy/Warning/Failed), destination
	•	Users need confidence, not hidden background jobs

6. Failure Visibility
	•	If backup fails: show reason + suggested fix
	•	Example: "Backup hasn't run for 7 days — NAS unavailable"
	•	Silent backup failure is unacceptable

7. Protection Status (Product Feature)
	•	Protection Score (e.g. "Protection Status: 82%")
	•	Per-capability breakdown: Books protected ✅, Music protected ✅, Smart Home not protected ⚠️
	•	Encourages setup completion, creates strong product experience

8. Future Extension — Snapshot Recovery (not MVP)
	•	Last 7 days, accidental deletion rollback, previous-state recovery

⸻

⚠️ Product Constraints
	•	DO: capability-aware backup, user-facing language, visible trust indicators
	•	DO NOT: expose rsync, expose cron, expose shell scripts, expose Docker backup docs, expose backend-specific backup mechanics
	•	Never make users think like sysadmins

⸻

✅ Acceptance Criteria
	•	User can choose a backup destination in < 1 minute
	•	User can understand what is protected without technical knowledge
	•	User can trust Haven as their long-term personal cloud platform
	•	Backup status is always visible
	•	Failure is never silent

⸻

🧠 Strategic Impact

Books + Music + Movies prove: Haven can manage personal services.
Backup proves: Haven can be trusted with them.

This is the trust milestone before Files.

🔥 One-liner: If Install → Start → Use made Haven useful, Backup → Trust makes Haven permanent.

⸻

🛠️ Implementation Sub-phases

16.1 — Backup Scope (Foundation) ✅
	•	New module: HavenBackup (depends on HavenCore only)
	•	BackupScope: reads StoredServiceState + Bundle.storage → produces paths to back up per capability
	•	BackupManifest: Codable struct describing backup contents (version, date, per-capability entries)
	•	BackupSettings: Codable config (destination, schedule, enabled capabilities, last backup info)
	•	BackupHealth: value type (status, protection score, per-capability protection)
	•	Tests: scope produces correct paths, manifest round-trips, settings persist

16.2 — Backup Engine (Core Logic) ✅
	•	BackupEngine: performs backup (copy content/config/state → export credentials → write manifest)
	•	Per-capability named root folders (Books/, Music/, Movies/) with data/ + config/ + state/ + credentials/ layout
	•	Incremental media sync: compares size + modification date, skips unchanged, removes orphans
	•	Credentials: export typed UserDefaults keys as credentials.json sidecar
	•	Atomic per-capability: finish one before starting next; partial backup is valid
	•	Per-file progress reporting for media content
	•	Tests: backup layout, incremental sync, manifests, config/state/credentials

16.3 — Backup Scheduler ✅
	•	In-process Timer (checks on launch + hourly)
	•	Wired into ServiceManager on app load and backup settings changes
	•	Triggers BackupEngine.backupAll() in background Task when overdue
	•	Tests: fires when overdue, skips when not due, manual-only never auto-fires

16.4 — Settings UI ✅
	•	Dedicated Backup tab in sidebar (not a section in Settings)
	•	Per-capability destination picker via NSOpenPanel
	•	Schedule picker (Daily, Every 3 Days, Weekly, Manual Only)
	•	"Back Up Now" button with progress spinner and per-file status
	•	BackupSettings persisted via UserDefaults

16.5 — Protection Status ✅
	•	ProtectionStatusView: circular progress ring (0-100%), animated, color-coded
	•	Per-capability rows with last backup date, "not backed up yet", or "not configured"
	•	BackupHealthBanner: compact banner on HomeView (warnings/failures only, taps to Backup tab)
	•	Sidebar badge on Backup tab for overdue/warning/failure states

16.6 — Restore Flow ❌ REMOVED
	•	Restore UI and engine restore APIs removed from MVP scope
	•	Backup remains focused on protection status, scheduled copies, and clear failure visibility

16.7 — Failure Visibility
	•	Error categorization: destination unreachable, disk full, permission denied, partial failure
	•	Overdue detection based on schedule
	•	Orange/red warnings with reason + suggested fix

Not in v1: snapshot recovery, launchd scheduling, encryption, cloud destinations

⸻


🎯 Phase 17 — Consistency

🎯 Goal

Make Books, Music, and Movies feel like one product — not three separate open-source wrappers.
Every capability should have the same setup flow, the same folder management, and the same UI patterns.

17.1 — Unified Setup Wizard ✅
	•	SetupPhase lives in shared HavenFacade and all connectable capabilities expose setupPhase
	•	SetupWizardView is reusable and drives Books, Music, and Movies progressive setup
	•	Managed vs custom account choice exists for Books, Music, and Movies
	•	Wizard steps supported: Server ready → Account choice → Account created → Choose folder → Scanning
	•	Music first-run folder selection now runs in the shared setup wizard instead of being skipped

17.2 — Multi-Folder for All ✅
	•	BooksLibrary and MoviesLibrary have libraryPaths: [String]
	•	BooksFacade and MoviesFacade support addLibraryPath() / removeLibraryPath()
	•	Kavita API add/remove library folders is implemented
	•	BackupScope uses unified content_paths for all capabilities, with legacy fallbacks
	•	MusicLibrary has libraryPaths: [String]
	•	MusicFacade supports addLibraryPath() / removeLibraryPath()
	•	Navidrome multi-library support is wired through Haven's add/remove folder flow
	•	Primary Navidrome MusicFolder remains guarded because it is service configuration and requires reinstall to replace
	•	Music library card shows all paths with per-path add/remove

17.3 — Library Card & Menu Consistency ✅
	•	Books and Movies use matching stats → folder paths → action buttons → hint structure
	•	Music adopts the same multi-folder card structure
	•	Shared button set across all three: Add Folder, Open Folder, Check for New
	•	Open in Browser appears in Books, Music, and Movies toolbar menus/actions
	•	Music gets an Add Folder option
	•	Consistent hint text pattern per capability

17.4 — Shared Components 🔄
	•	SetupWizardView extracted and reused
	•	LibraryFolderRow extracted for path display + remove button
	•	Unified CapabilityUIState enum replaces BooksUIState/MusicUIState/MoviesUIState
	•	Shared centered card and stat count helpers extracted
	•	TODO: Reduce HomeView duplication — common structure, capability-specific content only

⸻


✅ Phase 18 — Service Update System

🎯 Goal

Move Haven from "installer" to "trusted long-term manager."

🔧 Milestones

18.1 — Update Metadata & Version Discovery ✅
	•	Add UpdateCandidate / ServiceUpdateState domain models
	•	Add GitHubReleaseClient for latest stable release discovery
	•	Compare upstream release tags against StoredArtifactInfo.version
	•	Keep installed version tracking in StoredArtifactInfo and service state

18.2 — Safe Atomic Update Engine ✅
	•	ServiceUpdateManager state machine implemented at the dependency boundary
	•	Dependency boundary added for artifact pipeline and runtime controller
	•	Sequencing enforced: Download → Validate → Stop → Replace → Restart → Healthcheck
	•	Rollback path implemented for replace/start/healthcheck failures in the manager flow
	•	ArtifactServiceUpdatePipeline wires ArtifactInstaller staging/promote/rollback
	•	LaunchdServiceUpdateRuntimeController wires stop/start/healthcheck integration
	•	StoredArtifactUpdateTransaction commits StoredArtifactInfo.version / updatedAt only after healthcheck
	•	Critical rule: Never leave partial state

18.3 — Update UI ✅
	•	"Update Available" badges added to service cards/details
	•	Progress states shown for checking, downloading, validating, stopping, replacing, restarting, healthchecking, rollback
	•	Recovery path added: Retry and Open Logs

18.4 — Verification ✅
	•	Unit tests for release discovery and version comparison implemented
	•	Unit tests for rollback state machine implemented
	•	Adapter tests for concrete staging/promote/rollback behavior implemented
	•	Runtime-controller tests for stop/start/healthcheck integration implemented
	•	UI/state tests for badges and progress mapping implemented

Scope note: Phase 18 supports GitHub-release artifact updates. Direct-url providers need provider-specific metadata discovery before they can participate.

Critical rule: Never leave partial state.

⸻

✅ Phase 19 — Haven App Updates

🎯 Goal

Let installed users receive new Haven releases from inside the app instead of manually replacing Haven.app.

🔧 Deliverables
	•	Add Sparkle 2 as the macOS app update framework
	•	Add a Settings action for user-initiated "Check for Updates"
	•	Read update availability from a signed appcast feed
	•	Require Developer ID signing, notarization, and Sparkle EdDSA signatures for public releases
	•	Keep service updates separate from Haven app updates
	•	Document the release process: bump version/build, build, sign, notarize, archive, generate appcast, upload

✅ Acceptance Criteria
	•	Settings shows whether app updates are configured
	•	"Check for Updates" is enabled only when Sparkle can check
	•	The app fails softly in development builds without production appcast credentials
	•	Public releases can update from one signed/notarized Haven.app to the next
	•	Current pre-Sparkle installs have a documented one-time manual update path

⸻

✅ Phase 20 — macOS Topbar Menu

🎯 Goal

Make Haven feel resident on macOS: closing the main window should not stop Haven, and core operations should remain available from the menu bar.

🔧 Deliverables
	•	Always-present macOS menu bar item while Haven is running
	•	Closing the main Haven window keeps the app process and menu bar item alive
	•	"Open Haven" menu action reopens/focuses the main window
	•	"Open at Login" toggle using the native macOS login item API
	•	Installed capabilities list with live service status from launchd
	•	Last backup summary with result/date/status
	•	"Back Up Now" menu action using the same backup path as the Backup tab

✅ Acceptance Criteria
	•	Haven menu item is visible after app launch
	•	User can close the main window and continue using Haven from the topbar
	•	User can reopen Haven from the menu
	•	Open-at-login preference reflects system state and can be toggled
	•	Capability status reflects whether services like Jellyfin are actually running
	•	Backup status is visible without opening the main window
	•	Backup can be started from the menu and shows in-progress state

⸻

📁 Phase 21 — Files 🔄 ACTIVE

🎯 Goal

Only build Files after a clear answer exists to: "Why Haven instead of Finder + iCloud?"
Until then: keep scope intentionally small.

🔧 Deliverables
	•	FilesFacade: root management, file listing, basic actions
	•	FileBrowserAdapter: config mapping, CLI/start control
	•	Native file browsing UI, folder selection

🛠️ Implementation Sub-phases

21.1 — Secure File Browser Foundation ✅ COMPLETE
	•	Built-in File Browser spec using GitHub release artifact
	•	No unauthenticated LAN access — Haven provisions managed credentials
	•	File Browser database bootstrap creates the managed user before launchd starts the server
	•	Credentials are omitted from launch arguments and sensitive planner settings are not persisted in service state
	•	FilesFacade exposes roots, current folder, file items, and safe file actions
	•	Native FilesHomeView: folder list, breadcrumb, open folder, new folder, rename, move to Trash
	•	Device access section: server address, username, password copy/reveal, QR code
	•	Backup scope includes the selected files root as user-visible content
	•	Verified against File Browser v2.63.2 quick setup and login flow
	•	Acceptance criteria:
	  - User can add Files and get a native Files tab
	  - User can browse the configured folder inside Haven
	  - User can create folders, rename items, and move items to Trash
	  - File Browser is available for browser/device access with Haven-managed credentials
	  - No `--noauth`, no terminal steps, no access outside selected roots

21.2 — Multi-Root Files Access ✅ COMPLETE
	•	Add/remove additional roots with a clear served-folder model
	•	Keep native UI, File Browser device access, and backup scope in sync
	•	Files setup wizard now asks managed vs custom account first, then prompts for the first served folder
	•	FilesFacade supports addRoot/removeRoot and persists the unified `content_paths` list
	•	Native Files UI exposes root switching, add-folder, and remove-folder actions
	•	File Browser serves a Haven-managed `data/served-roots` directory with one symlink per selected root
	•	Backup scope follows all selected roots through `content_paths`
	•	Verified File Browser v2.63.2 lists multiple served roots through `/api/resources/`

21.3 — Sharing & Recovery ⬜ NEXT
	•	Explicit local-network sharing UX
	•	Restore/rollback path once snapshot recovery exists

⸻

🔐 Phase 22 — Credential Convenience & Passwords Bridge ✅ COMPLETE

🎯 Goal

Make Haven-managed local service credentials understandable and easy to use across devices without overpromising direct Apple Passwords app insertion or showing macOS Keychain permission dialogs.

Context:
Apple Passwords / AutoFill integration is built around verified web domains, associated domains, user consent, and credential-provider extensions. Haven services usually run at local, dynamic addresses such as `http://MacBook.local:4533`, `localhost`, or LAN IPs. That makes silent Passwords app insertion the wrong primary path.

🔧 Deliverables
	•	Keep managed credentials in `UserDefaults` behind a shared credential-store boundary
	•	Defer Keychain storage after launch-blocking entitlements and repeated permission prompts proved too disruptive
	•	Create a shared credential store boundary for Books, Music, Movies, and Files
	•	Keep credential records typed by capability, backend, service URL, username, and credential purpose
	•	Keep existing saved credentials at the current `UserDefaults` keys
	•	Update backup export to read credentials through the shared credential boundary
	•	Add a unified Credentials panel/action for device access sections
	•	Panel shows local URL, LAN URL, username, password, and token URL when available
	•	Add per-field copy, copy-all, password reveal, QR code, and Open in Browser actions
	•	Add an optional "Open Passwords" helper action with clear manual-save guidance
	•	Prefer Safari/browser save-password prompts as the practical Apple Passwords bridge for local service URLs
	•	Document why Associated Domains / Shared Web Credentials require a stable HTTPS domain and are deferred
	•	Document why an AutoFill Credential Provider extension is deferred unless Haven becomes a credential provider

🛠️ Implementation Sub-phases

22.1 — UserDefaults Credential Store ✅
	•	Add a small HavenCredentialStore abstraction in a shared module
	•	Use `UserDefaults` for username/password/session values for now
	•	Preserve current facade APIs while replacing direct credential reads/writes internally
	•	Avoid runtime Keychain reads/writes so setup, refresh, reconnect, and device access never trigger macOS credential prompts
	•	Add tests for save, read, update, delete, migration no-op, and backup snapshots

22.2 — Migration & Backup Alignment ✅
	•	Keep Kavita, Navidrome, Jellyfin, and File Browser credential keys stable in `UserDefaults`
	•	Update uninstall/sign-out paths to clear credential-store records
	•	Update BackupCredentials to export through the credential store instead of raw defaults keys

22.3 — Credentials Convenience UI ✅
	•	Extract shared credential actions used by Books, Music, Movies, and Files
	•	Add Copy All as a single action for manual setup in mobile/TV/reader apps
	•	Add Open in Browser to encourage Safari/Passwords save prompts where available
	•	Keep passwords hidden by default and require explicit reveal/copy intent
	•	Make the local URL vs LAN URL distinction clear without exposing implementation details

22.4 — Apple Passwords Integration Gate ✅
	•	Do not build direct Passwords insertion for `localhost`, `.local`, or dynamic LAN URLs
	•	Re-evaluate Shared Web Credentials only if Haven ships a stable HTTPS domain model
	•	Re-evaluate AutoFill Credential Provider only if Haven should act as a password provider
	•	If a stable domain exists later, require Associated Domains entitlement, AASA hosting, signing/notarization validation, and user-consent testing
	•	Re-evaluate Keychain storage only with a signed build path and explicit no-prompt acceptance testing

✅ Acceptance Criteria
	•	No macOS Keychain dialogs appear during setup, refresh, reconnect, backup, or device access
	•	Existing users keep working with the current `UserDefaults` credential keys
	•	Books, Music, Movies, and Files can reconnect after app restart using stored credentials
	•	Sign out and uninstall clear the correct credential-store records
	•	Backup still includes the expected credential snapshot through the new boundary
	•	Device access UI gives users one place to copy or reveal all connection details
	•	Browser/Safari handoff path is documented and easy to find
	•	Roadmap explicitly records that true Apple Passwords integration is gated by stable HTTPS domains or a credential-provider strategy
	•	Roadmap explicitly records that Keychain storage is deferred until the UX is proven prompt-free

⸻

🧠 Strategic Evolution

Proven Pattern

Raw files → Haven cleanup → Backend engine → Cross-device access → Trust

Capability Map

Capability	Engine	Protocol	Status
Books	Kavita	OPDS	✅ Complete
Music	Navidrome	Subsonic	✅ Complete
Movies	Jellyfin	DLNA / HTTP	✅ Complete
Files	File Browser	HTTP	⬜ Next

Execution Strategy

Completed: Books → Music → Movies → Backup → Service Updates → App Updates → Topbar → Credential Convenience
Next: Files Sharing & Recovery
Each: full vertical slice, real usability, repeatable capability pattern.

Books validated: Haven can wrap a backend.
Music validated: Haven can scale the pattern.
Movies validated: Haven is a media platform.
Backup validated: Haven can be trusted long-term.

⸻

🔥 Product Direction

Haven is becoming:

private Netflix + Spotify + Kindle

—not a service manager.

⸻

Install → Start → Use (inside Haven)

⸻
UPDATED 03.05.26 (Phase 19 App Updates added; Topbar moved to 20; Files moved to 21)
UPDATED 04.05.26 (Phase 19 App Updates and Phase 20 Topbar complete; Phase 21 Files is next)
UPDATED 04.05.26 (Phase 21.1 Secure File Browser Foundation complete; Phase 21.2 Multi-Root Files Access is next)
UPDATED 04.05.26 (Phase 21.2 Multi-Root Files Access complete; Phase 21.3 Sharing & Recovery is next)
UPDATED 04.05.26 (Files and Music folder/account setup aligned with the shared setup wizard; Phase 21.3 remains next)
UPDATED 04.05.26 (Phase 22 Credential Convenience & Passwords Bridge implemented: shared UserDefaults-backed credential store, backup alignment, copy-all/Open/Passwords actions)
UPDATED 04.05.26 (Keychain storage rolled back after prompt-storm and launch-risk validation; UserDefaults remains the current credential storage path)
