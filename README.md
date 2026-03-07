# Typst Preview - macOS Quick Look Extension

Typst Preview is a macOS Quick Look extension for `.typ` files backed by the [Typst](https://typst.app/) compiler through a Rust FFI bridge.

The project contains two cooperating macOS targets:

- a Quick Look extension that renders Typst documents in Finder
- a host app that downloads missing Typst packages into a shared cache and shows runtime status

This lets Finder preview Typst files directly, including documents that depend on `@preview/...` packages.

## Features

- Quick Look preview for `.typ` files in Finder
- Rust-powered Typst compilation through a static library
- Automatic package download through the host app
- Shared package cache stored in an App Group container
- Transitive dependency handling for Typst packages
- Host app dashboard showing current downloads, queue state, errors, and installed packages

## System Requirements

- macOS 12.0+
- Xcode 14.0+
- Rust toolchain installed via [rustup](https://rustup.rs/)

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/WangHaoZhengMing/typst_preview.git
cd typst_preview
```

### 2. Install Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

### 3. Build the Rust library once

```bash
chmod +x scripts/*.sh
./scripts/build_rust.sh
```

This generates:

- `libs/libtypst_c.a`
- `libs/include/typst_c.h`

### 4. Open the Xcode project

```bash
open typst_preview.xcodeproj
```

### 5. Configure the Xcode build phase

See [scripts/XCODE_SETUP.md](scripts/XCODE_SETUP.md) for the full setup. The important part is adding a Run Script Phase before Swift compilation:

```bash
"${PROJECT_DIR}/scripts/build_rust.sh"
```

Recommended build settings:

- Header Search Paths: `$(PROJECT_DIR)/libs/include`
- Library Search Paths: `$(PROJECT_DIR)/libs`
- Other Linker Flags: `-ltypst_c -framework Security -framework CoreFoundation`

### 6. Build and run the host app

Run the `typst_preview` app target from Xcode at least once. The host app is responsible for:

- polling Quick Look package requests
- downloading missing packages
- installing them into the shared cache
- showing runtime status in its UI

After that, Quick Look on a `.typ` file in Finder should work.

## How Package Download Works

When a Typst file imports packages that are not installed yet:

1. the Quick Look extension detects the missing package
2. it writes a request into its sandbox container
3. the host app polls that request file
4. the host app downloads the package into the App Group cache at `~/Library/Group Containers/group.typst.preview/packages/`
5. if compilation reveals missing transitive package dependencies, they are requested and downloaded as well
6. retrying Quick Look uses the cached packages and renders the preview

In practice, the first preview of a package-heavy document may show a temporary downloading message. Subsequent previews use the installed cache.

## Project Structure

```text
typst_preview/
├── libtypst/                    # Rust Typst bridge and package resolution logic
│   ├── include/
│   │   └── typst_c.h
│   ├── src/
│   │   ├── ffi.rs
│   │   ├── package.rs
│   │   └── world.rs
│   └── Cargo.toml
├── libs/                        # Generated Rust build output
│   ├── libtypst_c.a
│   └── include/
│       └── typst_c.h
├── scripts/
│   ├── build_rust.sh
│   ├── README_BUILD.md
│   └── XCODE_SETUP.md
├── typst_preview/               # Host app
│   ├── ContentView.swift
│   ├── DownloaderDaemon.swift
│   ├── typst_preview.entitlements
│   └── typst_previewApp.swift
├── typst_quick_exten/           # Quick Look extension
│   ├── PreviewProvider.swift
│   ├── PreviewViewController.swift
│   ├── typst_quick_exten.entitlements
│   └── Info.plist
└── README.md
```

## Build Notes

### Automatic build from Xcode

During a normal Xcode build, `scripts/build_rust.sh`:

1. checks that `libtypst` exists
2. ensures the Rust target for the current CPU architecture is installed
3. builds the Rust static library
4. copies the library and header into `libs/`

### Manual rebuild

```bash
./scripts/build_rust.sh
```

### Updating `libtypst`

```bash
cd libtypst
git pull origin main
cd ..
./scripts/build_rust.sh
```

## Host App UI

The host app now acts as a small monitoring dashboard. It shows:

- current package being processed
- pending queue
- installed packages
- last event
- last error

This makes it easier to understand package download behavior without watching Console logs.

## Troubleshooting

### First build is slow

This is expected. Rust dependencies are downloaded and compiled on the first build.

### `cargo: command not found`

Install Rust and load Cargo into your shell:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

### Xcode cannot find `typst_c.h`

Check that:

- `libs/include/typst_c.h` exists
- Header Search Paths contains `$(PROJECT_DIR)/libs/include`

### Xcode cannot link `libtypst_c.a`

Check that:

- `libs/libtypst_c.a` exists
- Library Search Paths contains `$(PROJECT_DIR)/libs`
- Other Linker Flags contains `-ltypst_c -framework Security -framework CoreFoundation`

### Preview works for simple files but fails for package-based files

Make sure the host app is running. Package downloads are handled by the host app, not by the Quick Look extension itself.

### Need a clean rebuild

```bash
cd libtypst
cargo clean
cd ..
rm -rf libs/
./scripts/build_rust.sh
```

## Known Limitations

- First-time preview of documents with package dependencies can require an extra Quick Look retry
- Font availability
- can't work with images (due to MacOS)
- This project currently focuses on `@preview/...` style package workflows

## Documentation

- [scripts/XCODE_SETUP.md](scripts/XCODE_SETUP.md)
- [scripts/README_BUILD.md](scripts/README_BUILD.md)

## License

Apache License 2.0, consistent with Typst.

## Related Links

- [Typst Official Website](https://typst.app/)
- [Typst Documentation](https://typst.app/docs/)
- [libtypst Repository](https://github.com/WangHaoZhengMing/libtypst)
- [Rust Official Website](https://www.rust-lang.org/)
