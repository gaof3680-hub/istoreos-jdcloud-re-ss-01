#!/usr/bin/env python3
"""Deterministically add JDCloud RE-SS-01 (京东亚瑟 AX1800 Pro) device support to an
iStoreOS/OpenWrt qualcommax/ipq60xx tree. Robust against branch context drift.
Replaces the fragile `patch --fuzz=3` that mis-placed hunks (ipq-wifi infinite
recursion -> gmake segfault -> missing board-2.bin -> wifi dead).

Usage: apply_device_support.py <istoreos_root> <patch_file> <board_wifi_file>
"""
import os, re, sys

root, patch_file, board_file = sys.argv[1], sys.argv[2], sys.argv[3]

def rd(p):
    with open(p, encoding="utf-8", errors="replace") as f: return f.read()
def wr(p, s):
    with open(p, "w", encoding="utf-8", newline="") as f: f.write(s)
def die(msg):
    print("  ERROR: " + msg); sys.exit(1)

# ---- 1. DTS (new file) extracted from patch -------------------------------
dts_rel = "target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-re-ss-01.dts"
patch = rd(patch_file)
dts_lines, grab = [], False
for line in patch.splitlines():
    if line.startswith("+++ b/" + dts_rel):
        grab = True; continue
    if grab:
        if line.startswith("diff --git"): break
        if line.startswith("+") and not line.startswith("+++"):
            dts_lines.append(line[1:])
dts_path = os.path.join(root, dts_rel)
os.makedirs(os.path.dirname(dts_path), exist_ok=True)
wr(dts_path, "\n".join(dts_lines) + "\n")
if os.path.getsize(dts_path) < 1000: die("DTS extraction failed")
print("  [1/6] DTS written (%d bytes)" % os.path.getsize(dts_path))

# ---- 2. ipq60xx.mk : append Device define ----------------------------------
mk = os.path.join(root, "target/linux/qualcommax/image/ipq60xx.mk")
s = rd(mk)
if "jdcloud_re-ss-01" not in s:
    if not s.endswith("\n"): s += "\n"
    s += """
define Device/jdcloud_re-ss-01
\t$(call Device/FitImage)
\tDEVICE_VENDOR := JDCloud
\tDEVICE_MODEL := RE-SS-01
\tSOC := ipq6000
\tBLOCKSIZE := 64k
\tKERNEL_SIZE := 6144k
\tDEVICE_DTS_CONFIG := config@cp03-c2
\tDEVICE_PACKAGES := ipq-wifi-jdcloud_re-ss-01
endef
TARGET_DEVICES += jdcloud_re-ss-01
"""
    wr(mk, s)
print("  [2/6] ipq60xx.mk device appended")

# ---- 3. ipq-wifi Makefile --------------------------------------------------
iq = os.path.join(root, "package/firmware/ipq-wifi/Makefile")
s = rd(iq)
if "jdcloud_re-ss-01" not in s:
    lines = s.splitlines(keepends=True); out=[]; a1=False; a2=False
    for ln in lines:
        out.append(ln); r = ln.rstrip()
        if (not a1) and ("compex_wpq873" in ln) and r.endswith(chr(92)) and ("generate" not in ln):
            out.append("\tjdcloud_re-ss-01 " + chr(92) + "\n"); a1 = True
        if (not a2) and ln.startswith("$(eval $(call generate-ipq-wifi-package,compex_wpq873,"):
            out.append("$(eval $(call generate-ipq-wifi-package,jdcloud_re-ss-01,JDCloud RE-SS-01))\n"); a2 = True
    if not (a1 and a2): die("ipq-wifi anchors missing (ALLWIFI=%s gen=%s)" % (a1, a2))
    wr(iq, "".join(out))
print("  [3/6] ipq-wifi registered")

# ---- 4. 02_network ---------------------------------------------------------
net = os.path.join(root, "target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network")
s = rd(net)
if "jdcloud,re-ss-01" not in s:
    lines = s.splitlines(keepends=True); out=[]; f=False; done=False
    for ln in lines:
        out.append(ln)
        if "alfa-network,ap120c-ax)" in ln: f = True
        if f and ln.strip() == ";;" and not done:
            out.append("\tjdcloud,re-ss-01)\n")
            out.append('\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"\n')
            out.append("\t\t;;\n"); f=False; done=True
    if not done: die("02_network anchor missing")
    wr(net, "".join(out))
print("  [4/6] 02_network ports inserted")

# ---- 5. platform.sh (inside platform_do_upgrade) ---------------------------
plat = os.path.join(root, "target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh")
s = rd(plat)
if "jdcloud,re-ss-01" not in s:
    lines = s.splitlines(keepends=True); out=[]; f=False; done=False; infn=False
    blk = ["\tjdcloud,re-ss-01)\n",
           '\t\tlocal cfgpart=$(find_mmc_part "0:BOOTCONFIG")\n',
           '\t\tpart_num="$(hexdump -e \'1/1 "%01x|"\' -n 1 -s 148 -C $cfgpart | cut -f 1 -d "|" | head -n1)"\n',
           '\t\tif [ "$part_num" -eq "1" ]; then\n',
           '\t\t\tCI_KERNPART="0:HLOS_1"\n', '\t\t\tCI_ROOTPART="rootfs_1"\n',
           '\t\telse\n', '\t\t\tCI_KERNPART="0:HLOS"\n', '\t\t\tCI_ROOTPART="rootfs"\n',
           '\t\tfi\n', '\t\temmc_do_upgrade "$1"\n', "\t\t;;\n"]
    for ln in lines:
        out.append(ln)
        if ln.startswith("platform_do_upgrade()"): infn = True
        if infn and "cambiumnetworks,xe3-4)" in ln: f = True
        if f and ln.strip() == ";;" and not done:
            out.extend(blk); f=False; done=True
    if not done: die("platform.sh anchor missing")
    wr(plat, "".join(out))
print("  [5/6] platform.sh eMMC upgrade inserted")

# ---- 6. caldata (handle renamed 11-ath11-caldata / 11-ath11k-caldata) ------
cd_dir = os.path.join(root, "target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware")
cand = [f for f in os.listdir(cd_dir) if f.startswith("11-ath11") and "caldata" in f] if os.path.isdir(cd_dir) else []
if not cand: die("no ath11 caldata hotplug script found")
cal = os.path.join(cd_dir, cand[0]); s = rd(cal)
if "jdcloud,re-ss-01" not in s:
    lines = s.splitlines(keepends=True); out=[]; f=False; done=False; inf=False
    for ln in lines:
        out.append(ln)
        if re.match(r'^\s*case "\$board" in', ln): inf = True
        if inf and (not done) and ("cambiumnetworks,xe3-4)" in ln): f = True
        if f and ln.strip() == ";;" and not done:
            out.append("\tjdcloud,re-ss-01)\n")
            out.append('\t\tcaldata_extract_mmc "0:ART" 0x1000 0x10000\n')
            out.append("\t\t;;\n"); f=False; done=True; inf=False
    if not done: die("caldata anchor missing")
    wr(cal, "".join(out))
print("  [6/6] caldata inserted into " + cand[0])
print("Device support applied successfully.")
