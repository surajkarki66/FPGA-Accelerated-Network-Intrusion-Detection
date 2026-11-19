#!/usr/bin/env bash
# Build BOOT.BIN
# BOOT.BIN composition: FSBL + PMU Firmware (PMUFW) + FNN FPGA bitstream + Arm Trusted Firmware (ATF) + Device Tree Blob (DTB) + U-Boot.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/board/lib.sh"
load_config
need_cmd bootgen

if [[ ! -f "$BITSTREAM" ]]; then
  echo "Missing bitstream: $BITSTREAM — run board/build_bitstream.sh first" >&2
  exit 1
fi
for f in zynqmp_fsbl.elf pmufw.elf bl31.elf system.dtb u-boot.elf; do
  [[ -f "$FW_DIR/$f" ]] || {
    echo "Missing $FW_DIR/$f (clone Xilinx/soc-prebuilt-firmware @ xilinx_v2024.2)" >&2
    exit 1
  }
done

BIF="$OUT_DIR/fnn_linux.bif"
BOOT_OUT="$OUT_DIR/BOOT.BIN"
cat >"$BIF" <<EOF
the_ROM_image:
{
	[bootloader, destination_cpu=a53-0] $FW_DIR/zynqmp_fsbl.elf
	[pmufw_image] $FW_DIR/pmufw.elf
	[destination_device=pl] $BITSTREAM
	[destination_cpu=a53-0, exception_level=el-3, trustzone] $FW_DIR/bl31.elf
	[destination_cpu=a53-0, load=0x100000] $FW_DIR/system.dtb
	[destination_cpu=a53-0, exception_level=el-2] $FW_DIR/u-boot.elf
}
EOF

bootgen -arch zynqmp -image "$BIF" -w -o "$BOOT_OUT"
echo "OK: $BOOT_OUT"
