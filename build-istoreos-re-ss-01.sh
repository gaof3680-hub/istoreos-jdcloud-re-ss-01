#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-$HOME/istoreos-build}"
SRC_DIR="$WORK_DIR/istoreos"
BRANCH="${BRANCH:-istoreos-24.10}"
JOBS="${JOBS:-$(nproc)}"

echo "========================================"
echo "  iStoreOS 固件编译 — JDCloud RE-SS-01"
echo "  分支: $BRANCH"
echo "  并行: $JOBS 线程"
echo "  工作目录: $WORK_DIR"
echo "========================================"

mkdir -p "$WORK_DIR"

# ── 1. 克隆 / 更新源码 ──────────────────────────────────────
if [ ! -d "$SRC_DIR/.git" ]; then
  echo "[1/6] 克隆 iStoreOS 源码…"
  git clone --depth 1 --branch "$BRANCH" \
    https://github.com/istoreos/istoreos.git "$SRC_DIR"
else
  echo "[1/6] 更新 iStoreOS 源码…"
  git -C "$SRC_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$SRC_DIR" checkout "$BRANCH"
  git -C "$SRC_DIR" reset --hard "origin/$BRANCH"
fi

# ── 2. 确认设备支持已存在 ──────────────────────────────────
echo "[2/6] 确认 RE-SS-01 设备支持…"
DTS_FILE="$SRC_DIR/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-re-ss-01.dts"
BOARD_FILE="$SRC_DIR/package/firmware/ipq-wifi/files/board-jdcloud_re-ss-01.ipq6018"

if [ ! -f "$DTS_FILE" ]; then
  echo "  ✗ 设备树文件不存在: $DTS_FILE"
  echo "  请确认分支 $BRANCH 已包含 RE-SS-01 支持"
  exit 1
fi
if [ ! -f "$BOARD_FILE" ]; then
  echo "  ✗ Wi-Fi 板载数据不存在: $BOARD_FILE"
  echo "  请确认分支 $BRANCH 已包含 RE-SS-01 支持"
  exit 1
fi
echo "  ✓ 设备树已就绪"
echo "  ✓ Wi-Fi 板载数据已就绪"
echo "  ✓ 无需额外补丁 — 源码已内置 RE-SS-01 支持"

# ── 3. 更新 feeds ──────────────────────────────────────────
echo "[3/6] 更新 feeds…"
cd "$SRC_DIR"
./scripts/feeds update -a
./scripts/feeds install -a

# ── 4. 写入配置 ────────────────────────────────────────────
echo "[4/6] 写入编译配置…"
cp "$ROOT_DIR/configs/re-ss-01-stable.config" .config
make defconfig

# ── 5. 下载源码包 ──────────────────────────────────────────
echo "[5/6] 下载源码包…"
make download -j"$JOBS"

# ── 6. 编译 ────────────────────────────────────────────────
echo "[6/6] 开始编译（首次编译通常 1-3 小时）…"

# 安全措施：禁用 -Werror，避免因编译器警告导致编译中断
export EXTRA_CFLAGS="-Wno-error"
export EXTRA_CXXFLAGS="-Wno-error"

# 先用多线程编译；失败时用单线程 + 详细日志重试，便于定位错误
if ! make -j"$JOBS"; then
  echo "⚠ 多线程编译失败，切换到单线程详细模式重试…"
  make -j1 V=s
fi

# ── 输出结果 ───────────────────────────────────────────────
echo
echo "========================================"
echo "  编译完成！固件文件："
echo "========================================"
find "$SRC_DIR/bin/targets/qualcommax/ipq60xx" -maxdepth 1 -type f \
  \( -name "*jdcloud_re-ss-01*" -o -name "sha256sums" \) \
  -exec ls -lh {} \;
