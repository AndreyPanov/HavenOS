🧭 HavenOS — MVP+ Roadmap (Service Platform Evolution)

🎯 Vision

Haven turns a fresh Mac mini into a personal cloud with one-click service installs.

Haven abstracts:
	•	installation complexity
	•	runtime orchestration
	•	system dependencies

Into:

Install → Start → Open

⸻

🧱 Current State

✅ What works
	•	Spec-driven system (Capability → Bundle → RuntimeUnit)
	•	Native runtime execution
	•	Artifact copying (GitHub Release + direct-url, zip/tar.gz/tar.xz)
	•	launchd lifecycle management
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
	•	Navidrome pilot spec validated through full pipeline

⚠️ Remaining Limitations
	•	~~No runtime dependency validation~~ ✅ Resolved (DependencyValidator)
	•	No multi-service composition
	•	Pilot services not yet tested with live installs (spec-only so far)

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
8	Multi-Service	Unlock complex apps	⬜ Not started


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

3. Kavita (books)
	•	⬜ Spec not yet written
	•	library semantics, metadata handling

⸻

4. Calibre-Web (advanced)
	•	🔶 Python runtime specs exist (from earlier work)
	•	⬜ Needs schema v2 update (install steps, dependencies, storage)

⸻

✅ Acceptance Criteria
	•	All 4 services install via Haven
	•	No manual steps outside Haven
	•	No exposed system tooling

⸻

🔗 Phase 8 — Multi-Service Composition

🎯 Goal

Support complex apps (Nextcloud-class)

⸻

🔧 Deliverables
	•	runtime dependency graph
	•	startup ordering
	•	shared storage
	•	readiness checks

⸻

✅ Acceptance Criteria
	•	Can run app + DB stack
	•	Services start in correct order

⸻

⚠️ Risks
	•	Complexity explosion
	•	Turning Haven into Docker clone

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

🧭 Immediate Next Steps (Concrete)
	1.	Live install test: File Browser via GUI (simplest end-to-end)
	2.	Complete Navidrome live install (service reachable via HTTP)
	3.	Kavita pilot spec (library semantics)
	5.	Update Calibre-Web spec with schema v2 features

⸻

💬 Final Note

Haven is becoming:

The missing layer between macOS and self-hosted software

Not a dev tool.
Not a package manager.

👉 A consumer-grade service platform.