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

echo "[2/7] Applying RE-SS-01 device support (deterministic, no fuzz)..."
DTS_FILE="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-re-ss-01.dts"

if [ ! -f "$DTS_FILE" ]; then
  curl -sL "$REPO_RAW/patches/001-add-jdcloud-re-ss-01-support.patch" -o /tmp/re-ss-01.patch
  curl -sL "$REPO_RAW/files/board-jdcloud_re-ss-01.ipq6018" -o /tmp/board-jdcloud_re-ss-01.ipq6018
  [ -s /tmp/re-ss-01.patch ] || { echo "  ERROR: patch download failed"; exit 1; }
  [ -s /tmp/board-jdcloud_re-ss-01.ipq6018 ] || { echo "  ERROR: board wifi data download failed"; exit 1; }

  # Deterministic insertions (anchors + verification). Replaces the fragile
  # `patch --fuzz=3`, which mis-placed the ipq-wifi generate call inside its
  # own define -> infinite recursion -> gmake segfault -> board-2.bin missing.
  python3 "$ROOT_DIR/apply_device_support.py" "$SRC_DIR" /tmp/re-ss-01.patch /tmp/board-jdcloud_re-ss-01.ipq6018

  # Install board wifi data into ipq-wifi package files/ (picked up by wildcard)
  mkdir -p package/firmware/ipq-wifi/files
  cp /tmp/board-jdcloud_re-ss-01.ipq6018 package/firmware/ipq-wifi/files/board-jdcloud_re-ss-01.ipq6018

  # Verify every essential artifact landed correctly.
  echo "  Verifying..."
  bash -n target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network || { echo "  FAIL: 02_network syntax"; exit 1; }
  bash -n target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh || { echo "  FAIL: platform.sh syntax"; exit 1; }
  grep -q "jdcloud,re-ss-01" target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network || { echo "  FAIL: 02_network entry"; exit 1; }
  grep -q "jdcloud,re-ss-01" target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh || { echo "  FAIL: platform.sh entry"; exit 1; }
  grep -q "jdcloud,re-ss-01" target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11*-caldata || { echo "  FAIL: caldata entry"; exit 1; }
  grep -q "jdcloud_re-ss-01" target/linux/qualcommax/image/ipq60xx.mk || { echo "  FAIL: ipq60xx.mk device"; exit 1; }
  # ipq-wifi: generate call must be in the bottom call list, NOT inside the define
  GENLINE=$(grep -n 'generate-ipq-wifi-package,jdcloud_re-ss-01' package/firmware/ipq-wifi/Makefile | cut -d: -f1)
  FIRSTBOT=$(grep -n '^$(eval $(call generate-ipq-wifi-package,8devices_kiwi' package/firmware/ipq-wifi/Makefile | cut -d: -f1)
  [ -n "$GENLINE" ] && [ -n "$FIRSTBOT" ] && [ "$GENLINE" -gt "$FIRSTBOT" ] || { echo "  FAIL: ipq-wifi generate misplaced"; exit 1; }
  [ -f "$DTS_FILE" ] || { echo "  FAIL: DTS missing"; exit 1; }
  grep -q '&sdhc' "$DTS_FILE" || { echo "  FAIL: DTS missing sdhc"; exit 1; }
  echo "  All device support verified OK"
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
