# aerobeat-feature-boxing

Shared AeroBeat boxing gameplay feature package.

## GodotEnv development flow

This repo uses the AeroBeat Phase 2 GodotEnv package convention.

- Canonical dev/test manifest: `.testbed/addons.jsonc`
- Installed dev/test addons: `.testbed/addons/`
- GodotEnv cache: `.testbed/.addons/`
- Hidden workbench project: `.testbed/project.godot`
- Repo-local unit tests: `.testbed/tests/`
- Optional interactive/workbench scenes: `.testbed/scenes/`

The repo root is treated as the package/published boundary for downstream consumers. Day-to-day development, debugging, and validation happen from the hidden `.testbed/` workbench using the pinned OpenClaw toolchain: Godot `4.6.2 stable standard`.

### Restore dev/test dependencies

From the repo root:

```bash
cd .testbed
godotenv addons install
```

That installs the tagged `aerobeat-core` foundation plus GUT into `.testbed/addons/`.

### Open the workbench

From the repo root:

```bash
godot --editor --path .testbed
```

Use this `.testbed/` project as the canonical direct-development and bugfinding surface for boxing work.

### Import smoke check

From the repo root:

```bash
godot --headless --path .testbed --import
```

### Run unit tests

From the repo root:

```bash
godot --headless --path .testbed --script addons/gut/gut_cmdln.gd \
  -gdir=res://tests \
  -ginclude_subdirs \
  -gexit
```

### Validation notes

- `.testbed/addons.jsonc` is the only committed dev/test dependency contract.
- The manifest pins `aerobeat-core` to `v0.1.0` and GUT to `main` for the pilot flow.
- Repo-local unit tests live under `.testbed/tests/`; this package no longer uses a root-level `test/` directory.
- If interactive workbench scenes are added later, place them under `.testbed/scenes/`.
- The current package shape is consumed from the repo root (`subfolder: "/"`) for downstream installs.
