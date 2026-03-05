#!/bin/bash

# setup_project.sh - 项目初始化脚本
# 首次克隆项目后运行此脚本进行设置

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}===== Typst Preview 项目初始化 =====${NC}"

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# 1. 克隆 libtypst 仓库（如果不存在）
if [ ! -d "$PROJECT_DIR/libtypst" ]; then
    echo -e "${YELLOW}克隆 libtypst 仓库...${NC}"
    cd "$PROJECT_DIR"
    git clone https://github.com/WangHaoZhengMing/libtypst.git
    echo -e "${GREEN}✓ 克隆完成${NC}"
else
    echo -e "${GREEN}✓ libtypst 已存在${NC}"
fi

# 2. 检查 Rust 安装
if command -v cargo &> /dev/null; then
    RUST_VERSION=$(rustc --version)
    echo -e "${GREEN}✓ Rust 已安装: $RUST_VERSION${NC}"
else
    echo -e "${YELLOW}⚠ 未检测到 Rust${NC}"
    echo -e "${YELLOW}请访问 https://rustup.rs/ 安装 Rust${NC}"
    echo -e "${YELLOW}或运行: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh${NC}"
fi

# 3. 添加 Rust targets
if command -v rustup &> /dev/null; then
    echo -e "${YELLOW}添加 macOS 编译目标...${NC}"
    rustup target add x86_64-apple-darwin
    rustup target add aarch64-apple-darwin
    echo -e "${GREEN}✓ 编译目标已添加${NC}"
fi

# 4. 首次编译
echo -e "${YELLOW}进行首次编译...${NC}"
"$PROJECT_DIR/scripts/build_rust.sh"

# 5. 设置 .gitignore
if [ ! -f "$PROJECT_DIR/.gitignore" ]; then
    cat > "$PROJECT_DIR/.gitignore" << 'EOF'
# Xcode
*.xcodeproj/*
!*.xcodeproj/project.pbxproj
!*.xcodeproj/xcshareddata/
*.xcworkspace/*
!*.xcworkspace/contents.xcworkspacedata
!*.xcworkspace/xcshareddata/
xcuserdata/
*.moved-aside
*.swp
*~.nib
DerivedData/

# Rust compiled libraries
libs/
libtypst/target/

# macOS
.DS_Store
EOF
    echo -e "${GREEN}✓ 已创建 .gitignore${NC}"
fi

echo -e "${GREEN}===== 初始化完成 =====${NC}"
echo -e "${YELLOW}现在可以在 Xcode 中打开项目并编译了！${NC}"
