#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-$HOME/istoreos-build}"
SRC_DIR="$WORK_DIR/istoreos"
BRANCH="${BRANCH:-istoreos-24.10}"
JOBS="${JOBS:-$(nproc)}"

echo "工作目录: $WORK_DIR"
mkdir -p "$WORK_DIR"

if [ ! -d "$SRC_DIR/.git" ]; then
  git clone --depth 1 --branch "$BRANCH" https://github.com/istoreos/istoreos "$SRC_DIR"
else
  git -C "$SRC_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$SRC_DIR" checkout "$BRANCH"
  git -C "$SRC_DIR" reset --hard "origin/$BRANCH"
fi

echo "应用 JDCloud RE-SS-01 设备支持补丁"
git -C "$SRC_DIR" apply "$ROOT_DIR/patches/001-add-jdcloud-re-ss-01-support.patch"

echo "复制 RE-SS-01 Wi-Fi board data"
mkdir -p "$SRC_DIR/package/firmware/ipq-wifi/files"
cp "$ROOT_DIR/files/board-jdcloud_re-ss-01.ipq6018" "$SRC_DIR/package/firmware/ipq-wifi/files/"

echo "更新 feeds"
cd "$SRC_DIR"
./scripts/feeds update -a
./scripts/feeds install -a

echo "写入稳定优先配置"
cp "$ROOT_DIR/configs/re-ss-01-stable.config" .config
make defconfig

echo "开始下载源码包"
make download -j"$JOBS"

echo "开始编译，首次编译通常需要数小时"
make -j"$JOBS" V=s

echo
echo "编译完成。请检查以下输出："
find "$SRC_DIR/bin/targets/qualcommax/ipq60xx" -maxdepth 1 -type f \
  \( -name "*jdcloud_re-ss-01*" -o -name "sha256sums" \) -print
