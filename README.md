# Typst Preview - macOS 快速预览扩展

一个集成了 Typst 编译器的 macOS Quick Look 扩展。实现了简单的包管理器。

## 🚀 快速开始（一键设置）

```bash
# 1. 克隆项目
git clone <your-repo-url>
cd typst_preview

# 2. 运行初始化脚本（会自动克隆 libtypst、检查 Rust、编译库）
./scripts/setup_project.sh

# 3. 打开 Xcode 并配置（见下方）
open typst_preview.xcodeproj
```
## 📁 项目结构

```text
typst_preview/
├── libtypst/                  # Git Submodule: 指向 libtypst 官方仓库
├── libs/                      # 编译输出（自动生成，不提交，存放 .a 和 .h）
├── scripts/                   # 自动化编译和初始化脚本
├── typst_preview/             # Swift 主应用代码
└── typst_quick_exten/         # Quick Look 预览扩展代码

## 已知缺陷
无法正确识别字体，首次加载时间过长。

## ⚙️ Xcode 配置（首次设置）

详细步骤请查看：[**XCODE_SETUP.md**](XCODE_SETUP.md)

**快速版本：**

1. **添加 Build Phase** (在编译 Swift 代码之前运行)
   ```bash
   "${PROJECT_DIR}/scripts/build_rust.sh"
   ```

2. **Build Settings** 添加：
   - Header Search Paths: `$(PROJECT_DIR)/libs/include`
   - Library Search Paths: `$(PROJECT_DIR)/libs`
   - Other Linker Flags: `-ltypst_c -framework Security -framework CoreFoundation`

配置完成后，每次在 Xcode 中按 `Cmd+B` 编译时，会自动编译 Rust 代码！

## 📁 项目结构

```
typst_preview/
├── scripts/
│   ├── build_rust.sh          # 自动编译 Rust 脚本（Xcode 调用）
│   └── setup_project.sh       # 项目初始化脚本
├── libtypst/                  # Rust 源代码（git clone，不提交）
├── libs/                      # 编译输出（自动生成，不提交）
│   ├── libtypst_c.a          # Universal Binary 静态库
│   └── include/typst_c.h     # C 头文件
├── typst_preview/             # Swift 主应用
├── typst_quick_exten/         # Quick Look 扩展
└── README_BUILD.md            # 详细编译文档
```

## 📋 系统要求

- macOS 12.0+
- Xcode 14.0+
- Rust (通过 [rustup](https://rustup.rs/) 安装)

**安装 Rust：**
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

## 🔧 编译流程

### 自动编译（推荐）
在 Xcode 中直接编译，会自动处理一切！

### 手动编译 Rust 库
```bash
./scripts/build_rust.sh
```

### 更新 libtypst
```bash
cd libtypst
git pull origin main
cd ..
./scripts/build_rust.sh
```

## 📚 文档

- [**XCODE_SETUP.md**](XCODE_SETUP.md) - Xcode 详细配置步骤
- [**README_BUILD.md**](README_BUILD.md) - 完整编译文档和故障排除
- [libtypst GitHub](https://github.com/WangHaoZhengMing/libtypst) - Rust 源代码仓库

## 🐛 常见问题

### Q: 首次编译很慢？
A: 正常！Rust 首次编译需要下载依赖，约 5-10 分钟。后续编译只需几秒。

### Q: `cargo: command not found`？
A: 需要安装 Rust：`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`

### Q: 编译失败？
A: 查看详细的故障排除指南：[README_BUILD.md](README_BUILD.md#-故障排除)

### Q: Xcode 找不到库文件？
A: 
1. 确认 `libs/libtypst_c.a` 存在：`ls libs/libtypst_c.a`
2. 如不存在，手动运行：`./scripts/build_rust.sh`
3. 检查 Build Settings 配置是否正确

## 🎯 工作原理

1. Xcode Build Phase 触发 → 2. `build_rust.sh` 编译 Rust → 3. 生成 Universal Binary → 4. Swift 代码链接静态库 → 5. 完成编译


## 📄 许可证

Apache License 2.0 (与 Typst 相同)

## 🔗 相关链接

- [Typst 官网](https://typst.app/)
- [libtypst 仓库](https://github.com/WangHaoZhengMing/libtypst)
- [Rust 官方网站](https://www.rust-lang.org/)
