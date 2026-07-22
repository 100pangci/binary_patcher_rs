# Binary Patcher

[中文](README.md) | [日本語](README.ja.md)

---

A tool for creating and applying binary patches with full-directory workflow support.
Powered by [HDiffPatch](https://github.com/sisong/HDiffPatch) (`hdiffz` / `hpatchz`).

Requires the `hdiffz` and `hpatchz` binaries at runtime (see [Installation](#installation)).

## Features

- **Single-file patch** — create / apply a patch between two files
- **Directory bundle** — compare `Old/` vs `New/`, auto-generate `manifest.json` + patches + new files
- **One-click apply** — `apply_patch` reads the manifest, verifies SHA256, backs up originals, applies patches
- **One-click rollback** — `rollback_patch` restores backups and removes added files
- **Safety guarantees**:
  - Path traversal protection (`../` blocked)
  - SHA256 verification before and after patching
  - Automatic rollback on verification failure
  - Timestamped backups (no silent overwrite)
  - Manifest format validation

## Binaries

| Binary | Purpose |
|--------|---------|
| `binary_patcher` | Create patches (single-file and directory bundle) |
| `apply_patch` | Apply a patch bundle to a target directory |
| `rollback_patch` | Roll back a previously applied patch bundle |

## Installation

### Pre-built binaries

> **TODO**: Pre-built binaries are not yet available. Track [#1](https://github.com/100pangci/binary_patcher/issues/1) for release status.

### Build from source

```sh
git clone https://github.com/100pangci/binary_patcher.git
cd binary_patcher
cargo build --release
```

The compiled binaries are located at `target/release/`.

### HDiffPatch dependency

Download `hdiffz` and `hpatchz` from the [HDiffPatch releases page](https://github.com/sisong/HDiffPatch/releases).
Place them in one of the following locations:

| Location | Example |
|----------|---------|
| Same directory as the executable | `.` |
| `bin/` subdirectory | `./bin/` |
| Any directory in `PATH` | — |

## Quick Start

### 1. Generate a directory patch bundle

Directory layout:

```
Old/          ← place the old version here
New/          ← place the new version here
Patch/        ← created automatically
```

**First run:**

```sh
binary_patcher
```

The tool creates `Old/`, `New/`, `Patch/` directories. Populate `Old/` with the old version and `New/` with the new version.

**Second run:**

```sh
binary_patcher
```

The tool scans `Old/` and `New/`, computes SHA256 for every file, compares them, and generates:

- `Patch/manifest.json` — change manifest
- `Patch/**/*.patch` — binary patches for changed files
- `Patch/**/*.new` — copies of new files
- `Patch/README.txt` — instructions for end users

### 2. Apply a patch bundle

```
old-version root/
├── apply_patch
├── Patch/
│   ├── manifest.json
│   ├── ... .patch
│   └── ... .new
```

```sh
./apply_patch
```

The tool:

1. Validates each file against `old_sha256`
2. Backs up originals as `*.backup_before_patch`
3. Applies patches via `hpatchz`
4. Verifies output against `new_sha256`
5. Copies new files, deletes removed files

### 3. Roll back

```sh
./rollback_patch
```

Restores `*.backup_before_patch` backups and removes files that were added by the patch.

## CLI Reference

### `binary_patcher`

| Command | Description |
|---------|-------------|
| *(no arguments)* | Workspace mode: init `Old/`/`New/`/`Patch/`, then build bundle |
| `create <old> <new> <patch>` | Create a single patch file from two files |
| `apply <old> <patch> <output>` | Apply a single patch file |
| `bundle --base-dir <path>` | Build a bundle using a specific workspace directory |

### `apply_patch`

```sh
./apply_patch
```

### `rollback_patch`

```sh
./rollback_patch
```

## Project Structure

```
.
├── .github/workflows/
│   ├── ci.yml               # CI: cargo check + test (multi-platform)
│   └── build.yml            # Release: lint → test → build → GitHub Release
├── scripts/
│   └── build.ps1            # Windows one-click build + HDiffPatch download + package
├── Cargo.toml
├── src/
│   ├── main.rs              # binary_patcher entry point
│   ├── bin/
│   │   ├── apply_patch.rs   # apply_patch entry point
│   │   └── rollback_patch.rs# rollback_patch entry point
│   ├── cli.rs               # CLI argument parsing (clap)
│   ├── utils.rs             # SHA256, file ops, path safety, backup
│   ├── hdiffpatch.rs        # hdiffz/hpatchz discovery and invocation
│   ├── manifest.rs          # Manifest type, JSON serialization, validation
│   ├── bundle.rs            # Bundle creation (Old/New → Patch)
│   ├── apply.rs             # Bundle application logic
│   └── rollback.rs          # Bundle rollback logic
└── tests/
    └── integration_test.rs  # 20 tests (unit + full workflow)
```

## Security

| Feature | Description |
|---------|-------------|
| **Path traversal protection** | All manifest paths are validated; `../` escape attempts are rejected |
| **Manifest validation** | Schema, field types, and format version are verified on load |
| **SHA256 verification** | Files are hashed before and after patching; mismatches trigger automatic rollback |
| **Safe backups** | Backups use `.backup_before_patch` suffix; existing backups get a timestamp suffix |

## Development

### Prerequisites

- Rust 2024 edition (MSRV 1.85+)

### Commands

```sh
# Build
cargo build

# Run tests
cargo test

# Release build
cargo build --release
```

### Windows one-click build

```powershell
.\scripts\build.ps1
```

The script:
1. Runs `cargo build --release` to compile all three binaries
2. Downloads the latest HDiffPatch from GitHub (`hdiffz.exe` / `hpatchz.exe`)
3. Packages everything into `Releases/binary_patcher_toolkit.zip`

### CI / CD

This project uses GitHub Actions:

| Workflow | Trigger | Contents |
|----------|---------|----------|
| **CI** | push / PR | `cargo check` + `cargo test` (Windows / Linux / macOS) |
| **Build & Release** | tag `v*` / manual | check → test → `cargo build --release` → download HDiffPatch → package → publish to GitHub Release |

### TODO

- [ ] Provide pre-built binary downloads
- [ ] Windows binary signing

## Technical Stack

| Area | Choice |
|------|--------|
| Language | Rust (edition 2024) |
| CLI framework | clap (derive) |
| Serialization | serde + serde_json |
| Hashing | sha2 |
| Directory walk | walkdir |
| Error handling | anyhow |
| Patch engine | [HDiffPatch](https://github.com/sisong/HDiffPatch) (external binary) |

## License

Licensed under the [Mozilla Public License 2.0](LICENSE).

## Acknowledgements

- [HDiffPatch](https://github.com/sisong/HDiffPatch) — the binary diff / patch engine
- The original [binary_patcher](https://github.com/100pangci/binary_patcher) Python project
