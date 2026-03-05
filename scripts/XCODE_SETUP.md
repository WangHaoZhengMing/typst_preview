# Xcode 配置步骤

## ⚙️ 配置 Xcode 项目以自动编译 Rust

完成以下步骤后，每次在 Xcode 中编译时会自动编译 Rust 代码。

---

## 步骤 1: 添加 Build Phase

1. 在 Xcode 中打开 `typst_preview.xcodeproj`
2. 在左侧选择项目 (蓝色图标)
3. 选择 Target: **typst_preview**
4. 点击 **Build Phases** 标签
5. 点击左上角的 **+** 按钮
6. 选择 **New Run Script Phase**
7. 将新创建的 "Run Script" 拖动到最顶部（在 "Dependencies" 或 "Compile Sources" 之前）
8. 展开 "Run Script"
9. 在脚本框中输入：

```bash
# 自动编译 Rust libtypst
echo "正在编译 libtypst..."
"${PROJECT_DIR}/scripts/build_rust.sh"
```

10. 将这个 Phase 重命名为 "Build Rust Library" (可选但推荐)

---

## 步骤 2: 配置 Header Search Paths

1. 点击 **Build Settings** 标签
2. 搜索 "Header Search Paths"
3. 双击 **Header Search Paths** 的值区域
4. 点击 **+** 按钮
5. 添加：`$(PROJECT_DIR)/libs/include`
6. 确保设置为 **recursive** (可选)

---

## 步骤 3: 配置 Library Search Paths

1. 在 Build Settings 中搜索 "Library Search Paths"
2. 双击 **Library Search Paths** 的值区域
3. 点击 **+** 按钮
4. 添加：`$(PROJECT_DIR)/libs`

---

## 步骤 4: 配置 Linker Flags

1. 在 Build Settings 中搜索 "Other Linker Flags"
2. 双击 **Other Linker Flags** 的值区域
3. 添加以下标志（每行一个）：
   - `-ltypst_c`
   - `-framework`
   - `Security`
   - `-framework`
   - `CoreFoundation`

或者直接添加：`-ltypst_c -framework Security -framework CoreFoundation`

---

## 步骤 5: 更新 Bridging Header (如果使用 C API)

如果你的项目有 Bridging Header 文件（如 `typst_preview-Bridging-Header.h`）：

1. 打开该文件
2. 添加：
```c
#import "typst_c.h"
```

---

## ✅ 验证配置

1. 在 Xcode 中按 `Cmd+B` 编译
2. 查看编译日志，应该看到：
   ```
   正在编译 libtypst...
   ===== 开始编译 libtypst =====
   ...
   ✓ 编译成功！
   ```
3. 如果编译成功，配置完成！

---

## 🎯 快速命令行测试

在配置 Xcode 之前，可以先测试编译脚本：

```bash
cd /Users/hua/Documents/typst_preview
./scripts/setup_project.sh
```

这会：
- 克隆 libtypst 仓库
- 检查 Rust 安装
- 执行首次编译
- 生成 `libs/libtypst_c.a` 和头文件

---

## 📸 配置截图参考

### Build Phases - Run Script
```
▼ Run Script: Build Rust Library
  Shell: /bin/sh
  
  Script:
  # 自动编译 Rust libtypst
  echo "正在编译 libtypst..."
  "${PROJECT_DIR}/scripts/build_rust.sh"
  
  ☑️ Show environment variables in build log (可选)
```

### Build Settings - Search Paths
```
Header Search Paths:
  $(PROJECT_DIR)/libs/include

Library Search Paths:
  $(PROJECT_DIR)/libs
```

### Build Settings - Linker Flags
```
Other Linker Flags:
  -ltypst_c -framework Security -framework CoreFoundation
```

---

## 故障排除

### 问题：Xcode 报错 "libtypst_c.a not found"

**检查：**
1. 运行 `ls libs/libtypst_c.a` 确认文件存在
2. 如果不存在，手动运行：`./scripts/build_rust.sh`
3. 检查 Build Settings → Library Search Paths 是否正确

### 问题：头文件找不到

**检查：**
1. 运行 `ls libs/include/typst_c.h` 确认文件存在
2. 检查 Build Settings → Header Search Paths 是否正确

### 问题：Build Phase 脚本不执行

**检查：**
1. 确认 Run Script 位于所有编译步骤之前
2. 确认脚本有执行权限：`ls -l scripts/build_rust.sh`
3. 应该显示 `-rwxr-xr-x`

---

## 完成！

配置完成后，你只需要：
1. 打开 Xcode
2. 按 `Cmd+B` 编译
3. 一切自动完成！✨
