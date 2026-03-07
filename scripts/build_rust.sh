# build_rust.sh - 自动编译libtypst Rust代码
# 此脚本会在Xcode编译前自动运行

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}===== 开始编译 libtypst =====${NC}"

# 项目根目录
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
RUST_DIR="$PROJECT_DIR/libtypst"
OUTPUT_DIR="$PROJECT_DIR/libs"

# Xcode 的编译环境中可能没有包含用户的 PATH，因此手动添加 Rust 环境变量
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi
export PATH="$HOME/.cargo/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# 检查Rust是否安装
if ! command -v cargo &> /dev/null; then
    echo -e "${RED}错误: 未找到 cargo (Rust)${NC}"
    echo -e "${YELLOW}请访问 https://rustup.rs/ 安装 Rust${NC}"
    exit 1
fi

# 检查libtypst目录是否存在且包含 Cargo.toml
if [ ! -d "$RUST_DIR" ] || [ ! -f "$RUST_DIR/Cargo.toml" ]; then
    echo -e "${YELLOW}未找到完整的 libtypst 项目，正在从GitHub克隆...${NC}"
    cd "$PROJECT_DIR"
    
    # 如果目录存在但并不完整，先删除它以避免 git clone 报错
    if [ -d "$RUST_DIR" ]; then
        rm -rf "$RUST_DIR"
    fi
    
    git clone https://github.com/WangHaoZhengMing/libtypst.git
    if [ $? -ne 0 ]; then
        echo -e "${RED}克隆失败，请检查网络连接${NC}"
        exit 1
    fi
fi

# 进入Rust项目目录
cd "$RUST_DIR"

# 检查是否需要重新编译
if [ -f "$OUTPUT_DIR/libtypst_c.a" ]; then
    # 检查源代码是否有更新
    if [ "$OUTPUT_DIR/libtypst_c.a" -nt "Cargo.toml" ] && [ "$OUTPUT_DIR/libtypst_c.a" -nt "src/lib.rs" ]; then
        echo -e "${GREEN}libtypst 已是最新版本，跳过编译${NC}"
        exit 0
    fi
fi

# 1. 检测当前的 CPU 架构并设置对应的 Rust Target
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    RUST_TARGET="aarch64-apple-darwin"
    echo -e "${GREEN}检测到 Apple Silicon (arm64) 架构${NC}"
elif [ "$ARCH" = "x86_64" ]; then
    RUST_TARGET="x86_64-apple-darwin"
    echo -e "${GREEN}检测到 Intel (x86_64) 架构${NC}"
else
    echo -e "${RED}错误: 未知的 CPU 架构 ($ARCH)${NC}"
    exit 1
fi

echo -e "${GREEN}编译 libtypst (Release 模式, $ARCH)...${NC}"

# 2. 仅安装当前架构的 target（如果还没安装）
rustup target add $RUST_TARGET 2>/dev/null || true

# 3. 仅编译当前架构的版本
echo -e "${YELLOW}执行 cargo build...${NC}"
cargo build --release --target $RUST_TARGET

# 创建输出目录
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/include"

# 4. 直接复制静态库（无需使用 lipo）
echo -e "${YELLOW}复制静态库文件...${NC}"
cp "$RUST_DIR/target/$RUST_TARGET/release/libtypst_c.a" "$OUTPUT_DIR/libtypst_c.a"

# 复制头文件
if [ -f "$RUST_DIR/include/typst_c.h" ]; then
    cp "$RUST_DIR/include/typst_c.h" "$OUTPUT_DIR/include/"
    echo -e "${GREEN}已复制头文件到 libs/include/${NC}"
elif [ -f "$RUST_DIR/target/release/typst_c.h" ]; then
    cp "$RUST_DIR/target/release/typst_c.h" "$OUTPUT_DIR/include/"
    echo -e "${GREEN}已复制头文件到 libs/include/${NC}"
fi

# 验证输出
if [ -f "$OUTPUT_DIR/libtypst_c.a" ]; then
    echo -e "${GREEN}✓ 编译成功！${NC}"
    echo -e "${GREEN}  静态库: $OUTPUT_DIR/libtypst_c.a${NC}"
    
    # 使用 file 命令显示库的信息
    echo -e "${YELLOW}库信息:${NC}"
    file "$OUTPUT_DIR/libtypst_c.a"
    
    # 显示文件大小
    SIZE=$(du -h "$OUTPUT_DIR/libtypst_c.a" | awk '{print $1}')
    echo -e "${GREEN}  文件大小: $SIZE${NC}"
else
    echo -e "${RED}✗ 编译失败${NC}"
    exit 1
fi

echo -e "${GREEN}===== 编译完成 =====${NC}"