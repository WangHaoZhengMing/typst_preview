# Typst Preview - macOS Quick Look Extension

A macOS Quick Look extension that integrates the [Typst](https://typst.app/) compiler, enabling native preview of `.typ` files directly in Finder.

[Typst](https://typst.app/) is a modern markup-based typesetting system designed as an alternative to LaTeX. This extension allows you to preview Typst documents in macOS Finder without opening them in an editor.

## ✨ Features

- 🔍 Quick Look preview for `.typ` Typst files
- 🚀 Native macOS integration
- 📦 Built-in Typst compiler (via Rust FFI)
- 🎨 Fast preview generation

## 📋 System Requirements

- macOS 12.0+
- Xcode 14.0+
- Rust toolchain (installed via [rustup](https://rustup.rs/))

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/WangHaoZhengMing/typst_preview.git
cd typst_preview
```

### 2. Install Rust (if not already installed)

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

### 3. Initialize the Project

Run the setup script to clone dependencies and build the Rust library:

```bash
chmod +x scripts/*.sh
./scripts/setup_project.sh
```

This will:
- Clone the `libtypst` repository (Rust wrapper for Typst)
- Add necessary Rust compilation targets
- Build the Rust library for your architecture
- Generate `libs/libtypst_c.a` static library and header files

### 4. Open in Xcode

```bash
open typst_preview.xcodeproj
```

### 5. Configure Xcode Build Settings (First Time Only)

See detailed instructions: [scripts/XCODE_SETUP.md](scripts/XCODE_SETUP.md)

**Quick configuration:**

1. **Add Build Phase** (to run before compiling Swift code):
   - Target → Build Phases → + → New Run Script Phase
   - Add: `"${PROJECT_DIR}/scripts/build_rust.sh"`
   - Move it to the top (before "Compile Sources")

2. **Configure Build Settings**:
   - **Header Search Paths**: `$(PROJECT_DIR)/libs/include`
   - **Library Search Paths**: `$(PROJECT_DIR)/libs`
   - **Other Linker Flags**: `-ltypst_c -framework Security -framework CoreFoundation`

### 6. Build and Run

Press `Cmd+B` in Xcode to build. The build script will automatically compile the Rust library if needed.

## 📁 Project Structure

```
typst_preview/
├── scripts/
│   ├── build_rust.sh          # Automatic Rust build script (called by Xcode)
│   ├── XCODE_SETUP.md         # Detailed Xcode configuration guide
│   └── README_BUILD.md        # Build documentation and troubleshooting
├── libtypst/                  # Git submodule: Rust bindings for Typst
├── libs/                      # Build output (auto-generated, not committed)
│   ├── libtypst_c.a          # Static library (current architecture)
│   └── include/
│       └── typst_c.h         # C header file
├── typst_preview/             # Main Swift application
│   ├── typst_previewApp.swift
│   ├── ContentView.swift
│   └── typst_preview-Bridging-Header.h
├── typst_quick_exten/         # Quick Look extension implementation
│   ├── PreviewViewController.swift
│   ├── PreviewProvider.swift
│   └── Info.plist
└── README.md
```

## 🔧 Build Process

### Automatic Build (Recommended)

When you build in Xcode (`Cmd+B`), the pre-build script automatically:
1. Checks if `libtypst` exists (clones it if missing)
2. Detects your CPU architecture (Apple Silicon or Intel)
3. Compiles Rust code for your architecture
4. Generates `libs/libtypst_c.a` static library
5. Copies header files to `libs/include/`

### Manual Build

To manually compile the Rust library:

```bash
./scripts/build_rust.sh
```

### Updating libtypst

To update the Typst compiler to the latest version:

```bash
cd libtypst
git pull origin main
cd ..
./scripts/build_rust.sh
```

## 📚 Documentation

- [scripts/XCODE_SETUP.md](scripts/XCODE_SETUP.md) - Detailed Xcode configuration steps
- [scripts/README_BUILD.md](scripts/README_BUILD.md) - Complete build documentation and troubleshooting

## 🐛 Troubleshooting

### Q: First build is very slow?
**A:** This is normal! Rust needs to download and compile dependencies on first build (~5-10 minutes). Subsequent builds are much faster (seconds).

### Q: `cargo: command not found` error?
**A:** Install Rust:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

### Q: Build fails in Xcode?
**A:** 
1. Check if `libs/libtypst_c.a` exists: `ls libs/libtypst_c.a`
2. If missing, run manually: `./scripts/build_rust.sh`
3. Verify Build Settings are configured correctly (see [scripts/XCODE_SETUP.md](scripts/XCODE_SETUP.md))

### Q: Xcode can't find header files?
**A:** 
1. Verify `libs/include/typst_c.h` exists
2. Check Build Settings → Header Search Paths includes `$(PROJECT_DIR)/libs/include`

### Q: More issues?
**A:** See the detailed troubleshooting guide: [scripts/README_BUILD.md](scripts/README_BUILD.md)

## ⚠️ Known Issues

- Font detection may not work correctly for some fonts
- Initial preview generation can be slow for large documents

## 🎯 How It Works

1. **Xcode Build Phase** triggers `build_rust.sh`
2. **Rust Compilation** builds Typst compiler bindings as a static library
3. **Swift Code Linking** links against the Rust static library via FFI
4. **Quick Look Extension** uses the compiled library to render Typst files
5. **macOS Integration** registers the extension for `.typ` files

## 📄 License

Apache License 2.0 (same as Typst)

## 🔗 Related Links

- [Typst Official Website](https://typst.app/)
- [Typst Documentation](https://typst.app/docs/)
- [libtypst Repository](https://github.com/WangHaoZhengMing/libtypst) - Rust bindings used by this project
- [Rust Official Website](https://www.rust-lang.org/)

## 🙏 Acknowledgments

This project uses the Typst compiler and builds upon the Rust ecosystem.
