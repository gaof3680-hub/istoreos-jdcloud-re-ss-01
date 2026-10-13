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

  CALDATA_EXCL='*/hotplug.d/firmware/11-ath11-caldata'
  if ! git apply --whitespace=fix --exclude="$CALDATA_EXCL" /tmp/re-ss-01.patch 2>/dev/null; then
    if ! patch -p1 --fuzz=3 --exclude="$CALDATA_EXCL" < /tmp/re-ss-01.patch 2>/dev/null; then
      echo "  ERROR: device patch (non-caldata part) failed to apply."
      exit 1
    fi
  fi
  echo "  Core device patch applied (dts/ipq60xx.mk/network/platform/ipq-wifi)"

  CALDATA=$(ls target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11*-caldata 2>/dev/null | head -1 || true)
  if [ -z "$CALDATA" ]; then
    echo "  ERROR: no ath11 caldata hotplug script found."
    exit 1
  fi
  if ! grep -q "jdcloud,re-ss-01" "$CALDATA"; then
    echo "  Inserting caldata entry into $CALDATA ..."
    awk '
      /^\tcambiumnetworks,xe3-4\)/ && !done { print; ins=1; next }
      ins && /^\t\t;;$/ {
        print "\tjdcloud,re-ss-01)"
        print "\t\tcaldata_extract_mmc \"0:ART\" 0x1000 0x10000"
        print "\t\t;;"
        ins=0; done=1
        next
      }
      { print }
    ' "$CALDATA" > /tmp/caldata.tmp
    mv /tmp/caldata.tmp "$CALDATA"
  else
    echo "  Caldata entry already present"
  fi

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
