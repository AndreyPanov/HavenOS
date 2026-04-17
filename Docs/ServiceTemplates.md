# Haven Service Templates

Five reusable templates that cover all current service patterns.
Goal: new service spec in < 30 minutes, zero guesswork.

---

## Template Matrix

| Template | Pilot | Runtime | Artifact | Config | Secrets | Dirs | Deps |
|----------|-------|---------|----------|--------|---------|------|------|
| single-binary-web-app | File Browser | native | github-release | CLI flags | — | 2 | — |
| archive-based-service | Navidrome | native | github-release | generated file | yes | 3-5 | optional |
| library-server | Kavita | native | github-release | generated file | optional | 2+ | — |
| python-web-app | Calibre-Web | python | pip install | runtime-created | — | 3-4 | optional |
| app-with-helper | (composite) | native | github-release | varies | varies | varies | **required** |

---

## 1. single-binary-web-app

**When to use:** Self-contained binary, all config via CLI flags, no config files.
**Pilot:** File Browser

### Default RuntimeUnit

```json
{
    "id": "haven.unit.SERVICEID",
    "bundleID": "haven.bundle.SERVICEID-basic",
    "runtimeType": "native",
    "installSource": "",
    "port": PORT,
    "artifact": {
        "type": "github-release",
        "repo": "OWNER/REPO",
        "version": "vVERSION",
        "assets": [
            { "os": "macos", "arch": "arm64", "file": "ASSET_arm64.tar.gz" },
            { "os": "macos", "arch": "x86_64", "file": "ASSET_amd64.tar.gz" }
        ],
        "archive": { "format": "tar.gz" }
    },
    "entrypoint": { "command": "BINARY_NAME" },
    "launchArguments": [
        "--port", "${port}",
        "--root", "${content_dir}",
        "--FLAG", "VALUE"
    ],
    "directories": {
        "data": "data",
        "content": "${CONTENT_SETTING_KEY}"
    },
    "install": {
        "steps": [
            { "action": "mkdir", "path": "${data_dir}" },
            { "action": "mkdir", "path": "${content_dir}" }
        ]
    },
    "healthcheck": {
        "type": "http",
        "target": "http://localhost:${port}/health",
        "intervalSeconds": 10,
        "retries": 3
    }
}
```

### Default Bundle Pattern

```json
{
    "settings": [
        { "key": "CONTENT_KEY", "label": "LABEL", "fieldType": "path", "defaultValue": "~/DEFAULT", "required": true },
        { "key": "port", "label": "Port", "fieldType": "integer", "defaultValue": "PORT" }
    ],
    "storage": {
        "data": { "persistent": true, "userVisible": false },
        "content": { "persistent": true, "userVisible": true }
    },
    "onboarding": {
        "steps": [
            { "type": "info", "title": "SERVICE is ready", "body": "..." },
            { "type": "action", "title": "Open SERVICE", "body": "...", "url": "http://localhost:${port}" },
            { "type": "info", "title": "Access from other devices", "body": "...",
              "fields": [{ "label": "Address", "value": "http://your-mac:${port}" }] }
        ]
    }
}
```

### Characteristics
- **Install steps:** mkdir only (2)
- **Secrets:** none
- **Config files:** none — everything via CLI flags
- **Dependencies:** none
- **Onboarding:** info → action → network info (3 steps)

### Required Fields
- `artifact.repo`, `artifact.version`, `artifact.assets`
- `entrypoint.command`
- `launchArguments` (must include `--port ${port}`)
- One `path` setting for content directory
- `healthcheck.target` endpoint

### Optional Fields
- `environment` (if app reads env vars)
- `dependencies` (unlikely for single-binary)

---

## 2. archive-based-service

**When to use:** Binary in archive, needs config file generation, possibly secrets.
**Pilot:** Navidrome

### Default RuntimeUnit

```json
{
    "id": "haven.unit.SERVICEID",
    "bundleID": "haven.bundle.SERVICEID-basic",
    "runtimeType": "native",
    "installSource": "",
    "port": PORT,
    "artifact": {
        "type": "github-release",
        "repo": "OWNER/REPO",
        "version": "vVERSION",
        "assets": [
            { "os": "macos", "arch": "arm64", "file": "ASSET_arm64.tar.gz" },
            { "os": "macos", "arch": "x86_64", "file": "ASSET_amd64.tar.gz" }
        ],
        "archive": { "format": "tar.gz" }
    },
    "entrypoint": { "command": "BINARY_NAME" },
    "launchArguments": ["--configfile", "${config_dir}/CONFIG_FILE"],
    "environment": {
        "ENV_KEY": "${template_var}"
    },
    "directories": {
        "data": "data",
        "config": "config",
        "cache": "cache",
        "logs": "logs",
        "content": "${CONTENT_SETTING_KEY}"
    },
    "install": {
        "steps": [
            { "action": "mkdir", "path": "${data_dir}" },
            { "action": "mkdir", "path": "${config_dir}" },
            { "action": "mkdir", "path": "${cache_dir}" },
            { "action": "mkdir", "path": "${logs_dir}" },
            { "action": "generateSecret", "path": "SECRET_VAR", "content": "32", "mode": "hex" },
            { "action": "writeFile", "path": "${config_dir}/CONFIG_FILE", "content": "CONFIG_CONTENT_WITH_${SECRET_VAR}" },
            { "action": "chmod", "path": "${config_dir}/CONFIG_FILE", "mode": "600" }
        ]
    },
    "dependencies": [
        { "id": "HELPER", "kind": "helperBinary", "required": false,
          "validateCommand": "HELPER --version", "description": "..." }
    ],
    "healthcheck": {
        "type": "http",
        "target": "http://localhost:${port}/HEALTH_ENDPOINT",
        "intervalSeconds": 15,
        "retries": 3
    }
}
```

### Default Bundle Pattern

```json
{
    "settings": [
        { "key": "CONTENT_KEY", "label": "LABEL", "fieldType": "path", "defaultValue": "~/DEFAULT", "required": true },
        { "key": "port", "label": "Port", "fieldType": "integer", "defaultValue": "PORT" }
    ],
    "storage": {
        "data": { "persistent": true, "userVisible": false },
        "config": { "persistent": true, "userVisible": false },
        "cache": { "persistent": false, "userVisible": false },
        "logs": { "persistent": false, "userVisible": false },
        "content": { "persistent": true, "userVisible": true }
    },
    "onboarding": {
        "steps": [
            { "type": "info", "title": "SERVICE is ready", "body": "..." },
            { "type": "info", "title": "Your content folder", "body": "...",
              "fields": [{ "label": "Location", "value": "${content_dir}" }] },
            { "type": "action", "title": "Create your account", "body": "...", "url": "http://localhost:${port}" },
            { "type": "info", "title": "Access from other devices", "body": "...",
              "fields": [{ "label": "Address", "value": "http://your-mac:${port}" }] }
        ]
    }
}
```

### Characteristics
- **Install steps:** 5-8 (mkdir + generateSecret + writeFile + chmod)
- **Secrets:** 1+ (session key, JWT token, etc.)
- **Config files:** 1 (TOML, JSON, YAML — generated from template)
- **Dependencies:** 0-2 optional helpers
- **Onboarding:** info → content → action → network (4 steps)

### Required Fields
- Everything from single-binary-web-app, plus:
- `install.steps` with generateSecret + writeFile + chmod
- `config` directory role
- Config file content template with `${secret_var}` placeholders

### Optional Fields
- `environment` (for apps that read env vars)
- `dependencies` (helper binaries)
- `artifact.archive.stripFirstDirectory` (if archive has wrapper dir)
- Additional directory roles (cache, logs)

---

## 3. library-server

**When to use:** App that manages a user's content library (books, music, comics, files).
Extends archive-based-service with user-facing content semantics.
**Pilots:** Kavita, also applies to Navidrome, File Browser

### What Makes It Different

Library-servers share a key pattern: the **content directory** maps to user-owned files
(~/Music, ~/Books, ~/Documents) that must:
- Survive uninstall (`persistent: true`)
- Be visible in UI (`userVisible: true`)
- Be configurable by the user (`path` setting, `required: true`)
- Resolve tilde paths (`~/Books` → `/Users/.../Books`)

### Default Directories

```json
{
    "directories": {
        "config": "config",
        "content": "${library_path}"
    },
    "// note": "content maps to user setting, resolved at plan time"
}
```

### Default Storage

```json
{
    "storage": {
        "config": { "persistent": true, "userVisible": false },
        "content": { "persistent": true, "userVisible": true }
    }
}
```

### Default Settings

```json
{
    "settings": [
        { "key": "library_path", "label": "Library folder", "fieldType": "path",
          "defaultValue": "~/CONTENT_DEFAULT", "required": true },
        { "key": "port", "label": "Port", "fieldType": "integer", "defaultValue": "PORT" }
    ]
}
```

### Onboarding Pattern

Library servers always include:
1. **"Your library is ready"** — reassurance + content folder location
2. **Account/access step** — action to open UI or show credentials
3. **"Access from other devices"** — network address

### Applies To
- **Kavita** (books/comics/manga) — `~/Books`
- **Navidrome** (music) — `~/Music`
- **File Browser** (files) — `~/Documents`
- **Calibre-Web** (ebooks) — `~/CalibreLibrary`

### Checklist
- [ ] `library_path` (or equivalent) setting with `fieldType: "path"`
- [ ] `content` directory role mapping to `${library_path}`
- [ ] `content` storage policy: `persistent: true, userVisible: true`
- [ ] Onboarding shows the resolved content path
- [ ] Tilde expansion tested (spec test with empty settings)

---

## 4. python-web-app

**When to use:** Python package from PyPI, run via `python -m module`.
**Pilot:** Calibre-Web

### Default RuntimeUnit

```json
{
    "id": "haven.unit.SERVICEID",
    "bundleID": "haven.bundle.SERVICEID-basic",
    "runtimeType": "python",
    "port": PORT,
    "python": {
        "package": "PYPI_PACKAGE",
        "version": "PINNED_VERSION",
        "entrypoint": {
            "module": "MODULE_NAME",
            "args": ["MODULE_ARGS"]
        }
    },
    "entrypoint": {
        "args": ["MODULE_ARGS"],
        "env": {
            "ENV_KEY": "${template_var}"
        }
    },
    "directories": {
        "config": "config",
        "data": "data",
        "logs": "logs",
        "content": "${CONTENT_SETTING_KEY}"
    },
    "install": {
        "steps": [
            { "action": "mkdir", "path": "${config_dir}" },
            { "action": "mkdir", "path": "${data_dir}" },
            { "action": "mkdir", "path": "${logs_dir}" }
        ]
    },
    "dependencies": [
        { "id": "HELPER", "kind": "helperBinary", "required": false,
          "validateCommand": "HELPER --version", "description": "..." }
    ],
    "healthcheck": {
        "type": "http",
        "target": "http://localhost:${port}/",
        "intervalSeconds": 15,
        "retries": 5
    }
}
```

### Characteristics
- **No artifact block** — PythonEnvironmentPreparer handles pip install
- **`runtimeType: "python"`** — triggers venv creation
- **`python.version` must be pinned** — deterministic installs
- **Install steps:** mkdir only (no binary to extract)
- **Secrets:** typically none (config via runtime DB or env vars)
- **Config files:** typically none (app creates DB at runtime)
- **Dependencies:** optional helpers for extended features
- **Healthcheck:** longer retries (5) — Python apps start slower
- **Onboarding:** often includes credentials step (default admin)

### What PythonEnvironmentPreparer Handles
- System Python discovery (deterministic: homebrew → /usr/local → /usr)
- Venv creation at `~/.haven/Installed/python/<unitID>/venv/`
- `pip install package==version`
- Module import validation
- Venv caching and atomic staging

### What Must Be in Spec
- `python.package` + `python.version` (required, pinned)
- `python.entrypoint.module` (required)
- `python.entrypoint.args` (module arguments, template-expanded)
- `entrypoint.env` (environment variables for the process)

### Required Fields
- `python.package`, `python.version`, `python.entrypoint.module`
- `port`
- At least `config` directory role
- `healthcheck`

### Optional Fields
- `python.entrypoint.args` (module CLI arguments)
- `entrypoint.env` (environment variables)
- `dependencies` (external helpers)
- `content` directory role (if library-server pattern)

---

## 5. app-with-helper

**When to use:** Service that requires external CLI tools to function.
Extends any base template with required dependency validation.
**Pilot:** Not yet tested (Calibre-Web has optional deps, no required ones)

### Dependency Block Pattern

```json
{
    "dependencies": [
        {
            "id": "BINARY_NAME",
            "kind": "helperBinary",
            "required": true,
            "validateCommand": "/opt/homebrew/bin/BINARY_NAME --version",
            "description": "User-facing explanation of what this enables."
        },
        {
            "id": "OPTIONAL_HELPER",
            "kind": "helperBinary",
            "required": false,
            "validateCommand": "HELPER --version",
            "description": "Optional: enables FEATURE."
        }
    ]
}
```

### Characteristics
- **At least one `required: true` dependency** — install fails if missing
- **Consumer-friendly error messages** — never expose tooling details
- **validateCommand uses absolute paths** — deterministic discovery
- **Can combine with any base template** — native or Python

### DependencyValidator Behavior
- Probes: `/opt/homebrew/bin` → `/usr/local/bin` → `/usr/bin`
- Required missing → `ExecutorError.dependencyMissing` (blocks install)
- Optional missing → warning only (install continues)
- Deduplicates across multiple runtime units

### Known Limitations
- Does not probe `/Applications/*.app/Contents/MacOS/` (Calibre.app)
- Does not probe user-installed Python packages
- No version checking beyond validateCommand exit code

### Example Services
- **Calibre-Web + format conversion**: ebook-convert (optional)
- **Navidrome + transcoding**: ffmpeg (optional)
- **Hypothetical Nextcloud**: requires PHP, MySQL (required)

---

## Cross-Template Patterns

### Always Present
Every Haven service spec includes these regardless of template:

| Component | Required | Notes |
|-----------|----------|-------|
| `capability.json` | yes | id, name, version, description, icon |
| `bundle.json` | yes | id, name, capability, runtimeUnits, settings |
| `runtimes.json` | yes | Array of RuntimeUnit objects |
| Port setting | yes | `fieldType: "integer"`, default value |
| Healthcheck | yes | HTTP preferred; at minimum `/` endpoint |
| Onboarding | yes | At least 2 steps: info + action |

### ID Convention
```
capability: haven.capability.<service>
bundle:     haven.bundle.<service>-basic
unit:       haven.unit.<service>
```

### Port Selection
- Avoid 5000 (macOS AirPlay)
- Avoid 8080, 3000, 8000 (common dev ports)
- Check https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers

---

## Implementation Recommendation

### Phase 1: JSON Skeletons (Immediate)

Store template skeletons in `Sources/HavenCLIKit/Templates/`:
```
Templates/
  single-binary-web-app/
    capability.json.template
    bundle.json.template
    runtimes.json.template
  archive-based-service/
    ...
  library-server/
    ...
  python-web-app/
    ...
  app-with-helper/
    ...
```

Each `.template` file uses `PLACEHOLDER` tokens (not `${var}` to avoid
confusion with Haven's runtime template system):

```json
{
    "id": "haven.capability.__SERVICE_ID__",
    "name": "__SERVICE_NAME__",
    "version": "__VERSION__",
    ...
}
```

### Phase 2: CLI Generator

Add a `haven new` command:
```
haven new --template single-binary-web-app \
          --id myservice \
          --name "My Service" \
          --repo owner/repo \
          --version v1.0.0 \
          --port 9090
```

This:
1. Copies template files to `~/.haven/Catalog/myservice/`
2. Replaces `__PLACEHOLDER__` tokens with provided values
3. Opens the generated files for review

### Phase 3: Validation

Add `haven validate <path>` that:
1. Runs SpecLoader on the folder
2. Reports any issues
3. Checks template-specific requirements (e.g., "library-server must have content path setting")

### Why Not Code Generation?

JSON templates are better than programmatic generators because:
- Spec authors see the full structure (no hidden defaults)
- Easy to customize after generation
- No code dependency — templates work with any editor
- Matches Haven's spec-driven philosophy

---

## Template Selection Flowchart

```
Is it a Python package from PyPI?
  YES → python-web-app
  NO  → Is it a single binary with CLI flags only?
    YES → single-binary-web-app
    NO  → Does it require external tools?
      YES → app-with-helper (extends one of the below)
      NO  → Does it need config file generation?
        YES → archive-based-service
        NO  → single-binary-web-app

Does it manage user content (music/books/files)?
  YES → Add library-server pattern (composable with any base)
```
