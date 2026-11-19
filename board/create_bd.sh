#!/usr/bin/env bash
# Create Vivado project + FNN block design (PS + SmartConnect + fpga_top).
# Re-packages IP first unless SKIP_PACKAGE=1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/board/lib.sh"
load_config_vivado
need_cmd vivado

if [[ "${SKIP_PACKAGE:-0}" != "1" ]]; then
  "$ROOT/board/package_fpga_top.sh"
fi

if [[ ! -f "$IP_REPO/component.xml" ]]; then
  echo "Missing $IP_REPO/component.xml — run board/package_fpga_top.sh" >&2
  exit 1
fi

echo "Creating BD project → $VIVADO_XPR"
vivado -mode batch -source "$ROOT/board/create_bd.tcl" \
  -tclargs "$VIVADO_PROJ" "$IP_REPO" "$BOARD_PART" "$FPGA_PART" "$FNN_BASE_ADDR" "fnn_bd"
echo "OK: $VIVADO_XPR"
echo "Next: board/build_bitstream.sh"
