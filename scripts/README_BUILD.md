# Typst Preview - 编译说明

## 🚀 快速开始

### 首次设置

1. **安装 Rust**（如果还没安装）
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   source $HOME/.cargo/env
   ```

2. **运行初始化脚本**
   ```bash
   cd /Users/hua/Documents/typst_preview
   chmod +x scripts/*.sh
   ./scripts/setup_project.sh
   ```

3. **在 Xcode 中打开项目**
   ```bash
   open typst_preview.xcodeproj
   ```

4. **直接编译运行** - Xcode 会自动编译 Rust 代码！

---

## 📋 工作原理

### 自动化编译流程

当你在 Xcode 中按下 `Cmd+B` 编译时：

1. **Pre-build Script** 自动运行 `scripts/build_rust.sh`
2. 脚本检查 `libtypst` 目录是否存在
   - 不存在：自动从 GitHub 克隆
   - 存在：检查是否需要重新编译
3. 使用 `cargo` 编译 Rust 代码为两个架构：
   - `x86_64-apple-darwin` (Intel Mac)
   - `aarch64-apple-darwin` (Apple Silicon)
4. 使用 `lipo` 合并为 Universal Binary
5. 输出到 `libs/libtypst_c.a`
6. 复制头文件到 `libs/include/typst_c.h`
7. Xcode 继续编译 Swift 代码并链接静态库

### 目录结构

```
typst_preview/
├── scripts/
│   ├── build_rust.sh       # Rust 自动编译脚本
│   └── setup_project.sh    # 项目初始化脚本
├── libtypst/               # Rust 源代码 (git clone)
│   ├── Cargo.toml
│   ├── src/
│   └── include/
├── libs/                   # 编译输出 (自动生成，不提交到 git)
│   ├── libtypst_c.a       # Universal Binary 静态库
│   └── include/
│       └── typst_c.h      # C 头文件
└── typst_preview/          # Swift 源代码
    └── ...
```

---

## 🔧 Xcode 配置

### Build Phases 配置

1. 打开 Xcode 项目
2. 选择 Target → Build Phases
3. 点击 `+` → New Run Script Phase
4. 拖动到最顶部（在 "Compile Sources" 之前）
5. 添加以下脚本：

```bash
# 自动编译 Rust libtypst
"${PROJECT_DIR}/scripts/build_rust.sh"
```

6. 勾选 "Show environment variables in build log"（可选，用于调试）

### Build Settings 配置

1. **Header Search Paths**
   - 添加：`$(PROJECT_DIR)/libs/include`

2. **Library Search Paths**
   - 添加：`$(PROJECT_DIR)/libs`

3. **Other Linker Flags**
   - 添加：
     ```
     -ltypst_c
     -framework Security
     -framework CoreFoundation
     ```

---

## 🛠️ 手动编译

如果需要单独编译 Rust 库：

```bash
# 编译 Rust 库
./scripts/build_rust.sh

# 或者进入 libtypst 目录手动编译
cd libtypst
cargo build --release --target x86_64-apple-darwin
cargo build --release --target aarch64-apple-darwin

# 手动创建 Universal Binary
lipo -create \
    target/x86_64-apple-darwin/release/libtypst_c.a \
    target/aarch64-apple-darwin/release/libtypst_c.a \
    -output ../libs/libtypst_c.a
```

---

## 🔄 更新 libtypst

当 GitHub 仓库有更新时：

```bash
cd libtypst
git pull origin main
cd ..
./scripts/build_rust.sh
```

---

## 📝 注意事项

1. **首次编译较慢** - Rust 编译需要下载依赖，首次可能需要 5-10 分钟
2. **增量编译很快** - 后续编译只需几秒钟
3. **不要提交 libs/ 目录** - 已在 `.gitignore` 中排除
4. **不要提交 libtypst/target/** - 已在 `.gitignore` 中排除
5. **需要网络连接** - 首次编译需要下载 Rust 依赖包

---

## 🐛 故障排除

### 问题 1: `cargo: command not found`

**解决方案：**
```bash
# 安装 Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# 添加到 shell 配置
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### 问题 2: 编译失败 - 缺少 target

**解决方案：**
```bash
rustup target add x86_64-apple-darwin
rustup target add aarch64-apple-darwin
```

### 问题 3: Xcode 找不到头文件

**解决方案：**
1. 确认 `libs/include/typst_c.h` 存在
2. 检查 Xcode Build Settings → Header Search Paths
3. 应该包含：`$(PROJECT_DIR)/libs/include`

### 问题 4: 链接错误

**解决方案：**
1. 确认 `libs/libtypst_c.a` 存在
2. 检查 Build Settings → Library Search Paths
3. 检查 Other Linker Flags 包含：
   ```
   -ltypst_c -framework Security -framework CoreFoundation
   ```

### 问题 5: 想要清理重新编译

**解决方案：**
```bash
# 清理 Rust 编译产物
cd libtypst
cargo clean

# 清理输出目录
cd ..
rm -rf libs/

# 重新编译
./scripts/build_rust.sh
```

---

## 🎯 一键部署命令

```bash
# 完整的从零开始部署
cd /Users/hua/Documents/typst_preview
chmod +x scripts/*.sh
./scripts/setup_project.sh
open typst_preview.xcodeproj
# 然后在 Xcode 中按 Cmd+B 编译
```

---

## 📚 相关资源

- [libtypst GitHub 仓库](https://github.com/WangHaoZhengMing/libtypst)
- [Rust 官方安装指南](https://rustup.rs/)
- [Typst 官方文档](https://typst.app/)
