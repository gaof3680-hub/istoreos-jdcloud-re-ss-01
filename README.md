# JDCloud RE-SS-01 定制 iStoreOS 编译包

这个编译包用于给 `JDCloud RE-SS-01` 定制编译 iStoreOS 固件，目标是稳定优先，同时保留这台 IPQ60xx 设备的基础性能能力。

## 适配目标

你的路由器应匹配以下标识：

```text
model=JDCloud RE-SS-01
board=jdcloud_re-ss-01
compatible=jdcloud,re-ss-01
target=qualcommax/ipq60xx
```

不要使用 `jdcloud_ax1800-pro`、`ap-cp03-c1`、`jdcloud,ax1800-pro` 的固件直接刷这台机器。

## 编译包内容

```text
patches/001-add-jdcloud-re-ss-01-support.patch
files/board-jdcloud_re-ss-01.ipq6018
configs/re-ss-01-stable.config
build-istoreos-re-ss-01.sh
.github/workflows/build-istoreos-re-ss-01.yml
```

补丁包含：

- 新增 `JDCloud RE-SS-01` 设备树。
- 新增 `jdcloud_re-ss-01` 镜像目标。
- 新增 `jdcloud,re-ss-01` LAN/WAN 初始化。
- 新增 eMMC 双分区 `sysupgrade` 写入逻辑。
- 新增 Wi-Fi 校准数据提取逻辑。
- 新增 `ipq-wifi-jdcloud_re-ss-01` 固件包声明。

## 本地编译

建议使用 Ubuntu 22.04/24.04、至少 4 核 CPU、8GB 内存、80GB 可用磁盘空间。

安装依赖后运行：

```sh
chmod +x ./build-istoreos-re-ss-01.sh
./build-istoreos-re-ss-01.sh
```

可选环境变量：

```sh
WORK_DIR=$HOME/istoreos-build JOBS=4 ./build-istoreos-re-ss-01.sh
```

编译完成后检查：

```sh
ls -lh $HOME/istoreos-build/istoreos/bin/targets/qualcommax/ipq60xx/*jdcloud_re-ss-01*
```

你要刷的是：

```text
*jdcloud_re-ss-01-squashfs-sysupgrade.bin
```

## GitHub Actions 云编译

1. 新建一个 GitHub 仓库。
2. 把本目录所有文件上传到仓库根目录。
3. 打开 `Actions`。
4. 选择 `Build iStoreOS for JDCloud RE-SS-01`。
5. 点击 `Run workflow`。
6. 编译完成后在 artifact 里下载固件。

## 验包方法

编译后先在电脑上检查：

```sh
tar -tf *jdcloud_re-ss-01*squashfs-sysupgrade.bin
tar -xOf *jdcloud_re-ss-01*squashfs-sysupgrade.bin sysupgrade-jdcloud_re-ss-01/CONTROL
strings -a *jdcloud_re-ss-01*squashfs-sysupgrade.bin | grep -E 'jdcloud_re-ss-01|jdcloud,re-ss-01|JDCloud RE-SS-01|supported_devices'
```

期望看到：

```text
sysupgrade-jdcloud_re-ss-01/
BOARD=jdcloud_re-ss-01
supported_devices:["jdcloud,re-ss-01"]
```

## 刷机建议

- 只刷 `sysupgrade.bin`，不要用其他型号的 `factory.bin`。
- 从你当前的 ImmortalWrt/OpenWrt 后台升级即可。
- 第一次切换到这版定制 iStoreOS，建议不要保留配置。
- 如果 LuCI 提示设备不兼容，不要强制刷。
- 刷机前备份配置，并准备好 TTL/U-Boot 救砖方案。

## 稳定和性能取舍

这个配置没有默认内置 OpenClash、AdGuardHome、Docker 等重型插件。建议系统刷好并稳定运行后，再通过 iStore 逐个安装需要的插件。

要发挥性能，优先使用：

- 有线主路由场景下开启系统自带的硬件/NSS 加速能力。
- 插件少装、按需安装。
- 不要同时运行多个高负载代理、广告过滤和 Docker 容器。

如果你追求极限 NSS 性能，可以后续再做专门的 NSS/ECM 优化分支；稳定优先时，不建议一开始就叠加大量第三方加速补丁。
