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
12.5	Books Usability	Device access, auto-organize, scan errors	✅ DONE
13	Replaceability	Validate backend swap	✅ DONE
14	Music (Navidrome)	Second capability — validate pattern scales	✅ DONE
14.5	Platform Hardening	Shared protocols, zero downcasts, lifecycle tests	✅ DONE
15	Movies (Jellyfin)	Third capability — video streaming	⬜ Not started
16	Smart Home (Home Assistant)	Expand to home automation	⬜ Not started
17	Service Updates	Version discovery + safe atomic updates	⬜ Not started
18	Backup + Recovery	Trust milestone — export/restore	⬜ Not started
19	Files	Basic file access (deferred)	⬜ Not started


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
	•	No Passwords app integration (Associated Domains requires HTTPS + static domain)
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

🎬 Phase 15 — Movies (Jellyfin)

🎯 Goal

Extend the proven Books + Music pattern to video:
Local files → Metadata → Streaming → Access on every device

Create the feeling of "My own private Netflix" without exposing infrastructure complexity.

⸻

🔧 Deliverables

1. MoviesFacade (Domain Layer — HavenFacade)
	•	MoviesLibrary: libraryPath, movieCount, showCount, scanStatus
	•	MoviesFacade protocol extending ConnectableFacade: setLibraryPath(), rescan()
	•	SetupPhase enum: waitingForServer, creatingAccount, awaitingLibraryPath,
	  awaitingLibraryType, creatingLibrary, scanning, complete

2. JellyfinAPIClient (Backend Layer)
	•	Auth: initial setup wizard API (multi-step), login, createAdmin
	•	Libraries: createLibrary, getLibraries, refreshLibrary, getItemCounts
	•	Health: /System/Ping (returns plain text "Jellyfin Server")
	•	X-Emby-Token header auth (not Bearer)
	•	All methods async/throws, Sendable struct

3. JellyfinMoviesFacade (Concrete Facade)
	•	Implements MoviesFacade + ConnectableFacade
	•	Setup wizard flow (replaces simple auto-connect):
	  - Health poll → run Jellyfin startup wizard via API → create admin → await user input
	  - setupPhase drives progressive UI (auto steps + user steps interleaved)
	  - Facade exposes setupPhase; view renders inline wizard from it
	•	Post-setup: standard auto-connect pattern (token → password → managed creds)
	•	Library path changeable via API (unlike Navidrome)
	•	Scan polling: longer timeouts (metadata + artwork downloads take minutes)
	•	Credential persistence: same UserDefaults pattern (haven.jellyfin.* keys)

4. JellyfinSpec (Built-in Catalog)
	•	Capability: haven.capability.jellyfin, icon: film, version from GitHub
	•	Settings: movies_path (default ~/Movies), port (default 8096)
	•	Artifact: GitHub Release tar.gz (macOS arm64 + x64)
	•	Install steps: mkdir (config, data, cache, logs), chmod
	•	No generateSecret needed (Jellyfin self-generates on first run)
	•	Healthcheck: HTTP GET /System/Ping, 15s interval, 3 retries

5. Movies UI — Inline Setup Wizard (NEW UX PATTERN)
	•	MoviesHomeView: standard 8-state pattern (stopped/starting/setup/ready/etc.)
	•	Setup state renders as progressive inline form (not a modal sheet):
	  - Steps appear as cards in a scrolling list
	  - Completed steps collapse to single line with checkmark
	  - New steps animate in below answered ones (.move + .opacity transition)
	  - Auto steps (server ready, account created) complete without user input
	  - User steps (folder picker, library type) show interactive controls
	  - Final step (scan started) shows progress, then transitions to ready view

	Setup wizard steps:
	  1. Server ready — auto, health poll, green checkmark when /System/Ping responds
	  2. Account created — auto, Haven runs setup wizard API, shows "Signed in as haven-admin"
	  3. Where are your movies? — user picks folder, default ~/Movies
	  4. What's in your library? — user picks: Movies & TV / Movies only / TV only
	  5. Library scan started — auto, creates library via API, shows scan progress
	  6. Done — animate out wizard, transition to ready view

	User makes exactly 2 decisions to go from install to streaming.

	Reusable: SetupWizardView component can be reused by Smart Home (Phase 16).

6. Device Access (Username + Password)
	•	MoviesDeviceAccessSection: server address + credentials (same pattern as Music)
	•	Per-field copy buttons with independent feedback
	•	QR code for server address
	•	Password visibility toggle

7. Client Guidance
	•	Collapsed helper section:
	  - TV: Jellyfin app (Apple TV, Fire TV, Roku, Android TV)
	  - iPhone/iPad: Swiftfin
	  - Android: Findroid
	  - Desktop: Browser (Jellyfin web UI)

8. Open in Browser
	•	Jellyfin web UI as secondary action in toolbar menu
	•	Sign Out option for custom accounts

⸻

⚠️ Product Constraints
	•	DO: focus on streaming experience, preserve backend abstraction, reuse Books + Music UI patterns
	•	DO NOT: expose transcoding settings, expose server admin UI as primary flow, rebuild media playback UI

⸻

🔑 Key Differences from Books + Music

	•	Setup wizard: Multi-step inline progressive form (not ConnectSheet modal)
	  — Jellyfin requires language → user → library → metadata config on first run
	  — Haven drives this via API, user only picks folder + content type
	•	Scan duration: Minutes to hours (metadata + artwork from TMDb/TVDb)
	  — Longer polling timeouts, "this may take a while" messaging
	•	Library path: Changeable via API after initial setup (like Kavita, unlike Navidrome)
	•	No content organization: Jellyfin handles messy folder structures (no LibraryOrganizer needed)
	•	Auth header: X-Emby-Token (not Bearer), different from Kavita/Navidrome
	•	Self-contained binary: No .NET dependency, no working directory workaround, no stripFirstDirectory

⸻

✅ Acceptance Criteria
	•	User can add movies folder, see metadata populate, stream to TV/phone in < 3 minutes
	•	No manual backend setup required
	•	Setup wizard completes with exactly 2 user decisions (folder + content type)
	•	Zero Jellyfin-specific terms in MoviesHomeView (uses any MoviesFacade only)

⸻

🏠 Phase 16 — Smart Home (Home Assistant)

🎯 Goal

Expand Haven from "media operating system" to "home operating system."
Create simple private smart home setup without cloud dependency.

Strategic principle: Do NOT build "Home Assistant UI wrapper." Build "Add smart home to your home." Simple, guided, native.

⸻

🔧 Deliverables

1. SmartHomeFacade
	•	Core supported concepts only: Lights, Sensors, Presence, Scenes, Remote access
	•	Not full Home Assistant parity

2. HomeAssistantAdapter
	•	Install + runtime, onboarding, device discovery, secure local access, remote access guidance

3. Guided Onboarding UX
	•	Device-first: "Add your first device" → Choose: Lights / Sensors / Cameras / Presence
	•	Not dashboard-first

4. Scene-first UX
	•	Examples: Good Morning, Away Mode, Night Mode
	•	Focus on outcomes, not entities

⸻

⚠️ Scope Control
	•	DO NOT: expose HA complexity, expose YAML, expose integrations list explosion
	•	Keep v1 intentionally narrow

⸻

🔄 Phase 17 — Service Update System

🎯 Goal

Move Haven from "installer" to "trusted long-term manager."

🔧 Deliverables

1. Version Discovery
	•	GitHub releases detection, stable version tracking

2. Safe Atomic Update Flow
	•	Download → Validate → Stop → Replace → Restart → Healthcheck → Rollback on failure

3. Update UI
	•	"Update Available" badges, update progress, recovery path

Critical rule: Never leave partial state.

⸻

💾 Phase 18 — Backup + Recovery Confidence

🎯 Goal

Answer the question: "What happens if my Mac mini dies?" — Trust milestone.

🔧 Deliverables
	•	Backup visibility
	•	Export settings
	•	Restore flow
	•	Recovery confidence UI

⸻

📁 Phase 19 — Files

🎯 Goal

Only build Files after a clear answer exists to: "Why Haven instead of Finder + iCloud?"
Until then: keep scope intentionally small.

🔧 Deliverables
	•	FilesFacade: root management, file listing, basic actions
	•	FileBrowserAdapter: config mapping, CLI/start control
	•	Native file browsing UI, folder selection

⸻

🧠 Strategic Evolution

Proven Pattern

Raw files → Haven cleanup → Backend engine → Cross-device access → Trust

Capability Map

Capability	Engine	Protocol	Status
Books	Kavita	OPDS	✅ Complete
Music	Navidrome	Subsonic	✅ Complete
Movies	Jellyfin	DLNA / HTTP	⬜ Next
Smart Home	Home Assistant	Local / Zigbee	⬜ Planned
Files	File Browser	HTTP	⬜ Deferred

Execution Strategy

Books → Music → Movies → Smart Home → Updates → Backup → Files
Each: full vertical slice, real usability, repeatable capability pattern.

Books validated: Haven can wrap a backend.
Music validated: Haven can scale the pattern.
Movies will validate: Haven can be a media platform.
Smart Home will validate: Haven is a home operating system.

⸻

🔥 Product Direction

Haven is becoming:

private Netflix + Spotify + Kindle + Smart Home

—not a service manager.

⸻

Install → Start → Use (inside Haven)

⸻
UPDATED 25.04.26 (Strategic reorder: Movies + Smart Home before Files, added Update + Backup phases)
