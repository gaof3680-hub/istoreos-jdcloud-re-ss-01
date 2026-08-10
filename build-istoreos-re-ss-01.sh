#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-$HOME/istoreos-build}"
SRC_DIR="$WORK_DIR/istoreos"
BRANCH="${BRANCH:-istoreos-24.10}"
JOBS="${JOBS:-$(nproc)}"
REPO_RAW="https://raw.githubusercontent.com/Zhao-allen/istoreos-jdcloud-re-ss-01/a1ee5b8c39737c5e40bdaba0e7dd6d494f7b7ef7"

echo "========================================"
echo "  iStoreOS Build - JDCloud RE-SS-01"
echo "  Branch: $BRANCH"
echo "========================================"

mkdir -p "$WORK_DIR"

if [ ! -d "$SRC_DIR/.git" ]; then
  echo "[1/7] Cloning iStoreOS..."
  git clone --depth 1 --branch "$BRANCH" https://github.com/istoreos/istoreos.git "$SRC_DIR"
else
  echo "[1/7] Updating iStoreOS..."
  git -C "$SRC_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$SRC_DIR" checkout "$BRANCH"
  git -C "$SRC_DIR" reset --hard "origin/$BRANCH"
fi

cd "$SRC_DIR"

echo "[2/7] Checking RE-SS-01 support..."
DTS_FILE="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-re-ss-01.dts"

if [ ! -f "$DTS_FILE" ]; then
  echo "  Downloading and applying device patch..."
  curl -sL "$REPO_RAW/patches/001-add-jdcloud-re-ss-01-support.patch" -o /tmp/re-ss-01.patch
  git apply --whitespace=fix /tmp/re-ss-01.patch 2>/dev/null || patch -p1 --fuzz=3 < /tmp/re-ss-01.patch 2>/dev/null || {
    echo "  Standard patch failed, applying manually..."
    DTS_DIR="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom"
    mkdir -p "$DTS_DIR"
    curl -sL "$REPO_RAW/patches/001-add-jdcloud-re-ss-01-support.patch" | head -5
    echo "  ERROR: Could not apply patch. Check repo structure."
    exit 1
  }

  mkdir -p package/firmware/ipq-wifi/files
  curl -sL "$REPO_RAW/files/board-jdcloud_re-ss-01.ipq6018" \
    -o package/firmware/ipq-wifi/files/board-jdcloud_re-ss-01.ipq6018
  echo "  Device support injected"
else
  echo "  Already supported"
fi

echo "[3/7] Updating feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

echo "[4/7] Writing config..."
cp "$ROOT_DIR/configs/re-ss-01-stable.config" .config
make defconfig

echo "[5/7] Downloading sources..."
make download -j"$JOBS"

echo "[6/7] Building (1-3 hours)..."
export EXTRA_CFLAGS="-Wno-error"
export EXTRA_CXXFLAGS="-Wno-error"
if ! make -j"$JOBS"; then
  echo "  Retrying single-thread..."
  make -j1 V=s
fi

echo "[7/7] Done!"
find bin/targets/qualcommax/ipq60xx -maxdepth 1 -type f \
  -name "*jdcloud_re-ss-01*" -exec ls -lh {} \;
