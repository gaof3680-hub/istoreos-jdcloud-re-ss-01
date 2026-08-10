# JDCloud RE-SS-01 iStoreOS 编译包

为 `JDCloud RE-SS-01` 路由器编译 iStoreOS 固件。iStoreOS `istoreos-24.10` 分支已内置该设备的完整支持，无需额外补丁。

## 设备标识

```text
model=JDCloud RE-SS-01
board=jdcloud_re-ss-01
compatible=jdcloud,re-ss-01
target=qualcommax/ipq60xx
SOC=ipq6000
```

## 编译包内容

```text
configs/re-ss-01-stable.config      # 编译配置（稳定优先）
build-istoreos-re-ss-01.sh          # 本地编译脚本
.github/workflows/build-istoreos-re-ss-01.yml  # GitHub Actions 云编译
```

## 源码已内置的支持

iStoreOS `istoreos-24.10` 分支已包含以下 RE-SS-01 支持：

- 设备树：`ipq6000-re-ss-01.dts`（LED、按键、eMMC、USB、网口）
- Wi-Fi 板载数据：`board-jdcloud_re-ss-01.ipq6018`
- ipq-wifi 固件包：`ipq-wifi-jdcloud_re-ss-01`
- caldata 提取：eMMC ART 分区校准数据
- 升级逻辑：eMMC 双分区（0:HLOS / 0:HLOS_1）sysupgrade
- 网络配置：LAN1-3 + WAN

## 本地编译

**环境要求**：Ubuntu 22.04+、4 核 CPU、8GB 内存、80GB 磁盘

```sh
chmod +x ./build-istoreos-re-ss-01.sh
./build-istoreos-re-ss-01.sh
```

可选环境变量：

```sh
WORK_DIR=$HOME/istoreos-build JOBS=4 ./build-istoreos-re-ss-01.sh
```

编译产物：

```sh
ls -lh $HOME/istoreos-build/istoreos/bin/targets/qualcommax/ipq60xx/*jdcloud_re-ss-01*
```

刷机使用 `*jdcloud_re-ss-01-squashfs-sysupgrade.bin`。

## GitHub Actions 云编译

1. 新建 GitHub 仓库，将本目录所有文件上传到根目录
2. 打开 `Actions` → 选择 `Build iStoreOS for JDCloud RE-SS-01`
3. 点击 `Run workflow`
4. 编译完成后在 Artifacts 下载固件

## 刷机须知

- 只刷 `sysupgrade.bin`，不要用其他型号的 `factory.bin`
- 从当前 ImmortalWrt/OpenWrt 后台直接 sysupgrade 升级
- 首次切换到 iStoreOS 建议不保留配置
- 刷机前备份配置，准备 TTL/U-Boot 救砖方案

## 稳定优先策略

配置未内置 OpenClash、AdGuardHome、Docker 等重型插件。建议系统稳定运行后通过 iStore 按需安装。
