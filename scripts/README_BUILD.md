# Typst Preview - Build Guide

This document describes the current build flow for Typst Preview.

The project is made of three cooperating pieces:

- the Rust static library in `libtypst/`
- the macOS host app in `typst_preview/`
- the Quick Look extension in `typst_quick_exten/`

The Rust library handles Typst compilation. The host app handles package download and cache management. The Quick Look extension renders previews in Finder.

## Quick Start

### 1. Install Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

### 2. Build the Rust library

From the repository root:

```bash
chmod +x scripts/*.sh
./scripts/build_rust.sh
```

This generates:

- `libs/libtypst_c.a`
- `libs/include/typst_c.h`

### 3. Open the Xcode project

```bash
open typst_preview.xcodeproj
```

### 4. Configure Xcode once

Add a Run Script Phase before Swift compilation:

```bash
"${PROJECT_DIR}/scripts/build_rust.sh"
```

Recommended Build Settings:

- Header Search Paths: `$(PROJECT_DIR)/libs/include`
- Library Search Paths: `$(PROJECT_DIR)/libs`
- Other Linker Flags: `-ltypst_c -framework Security -framework CoreFoundation`

Detailed steps are in [XCODE_SETUP.md](XCODE_SETUP.md).

### 5. Run the host app target

The host app must be run at least once because it:

- receives package download requests from the Quick Look extension
- downloads missing Typst packages
- installs them into the shared App Group cache
- exposes status in its UI

After that, Finder Quick Look can preview `.typ` files.

## Current Build Flow

### What `build_rust.sh` does

When called from Xcode or manually, `scripts/build_rust.sh`:

1. resolves the project and Rust source directories
2. loads Cargo into `PATH`
3. checks whether `libtypst/` exists and contains `Cargo.toml`
4. detects the current machine architecture
5. builds the Rust static library for the current architecture
6. copies the resulting library to `libs/libtypst_c.a`
7. copies `typst_c.h` into `libs/include/`

The script currently builds for the current architecture only, not as a universal binary.

## Directory Layout

```text
typst_preview/
├── libtypst/
│   ├── include/
│   │   └── typst_c.h
│   ├── src/
│   │   ├── ffi.rs
│   │   ├── package.rs
│   │   └── world.rs
│   └── Cargo.toml
├── libs/
│   ├── libtypst_c.a
│   └── include/
│       └── typst_c.h
├── scripts/
│   ├── build_rust.sh
│   ├── README_BUILD.md
│   └── XCODE_SETUP.md
├── typst_preview/
│   ├── ContentView.swift
│   ├── DownloaderDaemon.swift
│   ├── typst_preview.entitlements
│   └── typst_previewApp.swift
└── typst_quick_exten/
    ├── PreviewProvider.swift
    ├── PreviewViewController.swift
    ├── typst_quick_exten.entitlements
    └── Info.plist
```

## Manual Build Commands

### Rebuild the Rust library

```bash
./scripts/build_rust.sh
```

### Build directly with Cargo

```bash
cd libtypst
cargo build --release
```

If you build directly with Cargo, remember that Xcode links against the copied file in `libs/`, not the artifact in `target/`.

## Updating `libtypst`

```bash
cd libtypst
git pull origin main
cd ..
./scripts/build_rust.sh
```

## Package Download Runtime

The package workflow during preview is:

1. Quick Look scans the Typst file for direct package imports
2. if packages are missing, it writes a request into the extension sandbox
3. the host app polls that request file
4. the host app downloads packages into the App Group cache
5. if downloaded packages reference other package versions in their `.typ` sources, those transitive dependencies are also downloaded
6. Quick Look retries against the shared package cache

Shared package cache root:

```text
~/Library/Group Containers/group.typst.preview/packages/
```

## Troubleshooting

### `cargo: command not found`

Install Rust and load Cargo:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

### Xcode cannot find `typst_c.h`

Check:

- `libs/include/typst_c.h` exists
- Header Search Paths contains `$(PROJECT_DIR)/libs/include`

### Xcode cannot link `libtypst_c.a`

Check:

- `libs/libtypst_c.a` exists
- Library Search Paths contains `$(PROJECT_DIR)/libs`
- Other Linker Flags contains `-ltypst_c -framework Security -framework CoreFoundation`

### Quick Look works for simple files but fails for package-based files

Make sure the host app is running. Package download is handled by the host app, not by the Quick Look extension directly.

### Clean rebuild

```bash
cd libtypst
cargo clean
cd ..
rm -rf libs/
./scripts/build_rust.sh
```

## Notes

- The first Rust build is slow because dependencies must be downloaded and compiled.
- Subsequent builds are much faster.
- The host app UI shows current package, pending queue, installed packages, last event, and last error.
- The current package workflow is designed around Typst package imports such as `@preview/...`.

## Related Documents

- [../README.md](../README.md)
- [XCODE_SETUP.md](XCODE_SETUP.md)
