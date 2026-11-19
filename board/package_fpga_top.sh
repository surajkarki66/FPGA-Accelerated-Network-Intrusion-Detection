#!/usr/bin/env bash
# Package rtl/ as user.org:user:fpga_top:1.0 into $IP_REPO.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/board/lib.sh"
load_config_vivado
need_cmd vivado

if [[ ! -f "$ROOT/weights/generated/weights.mem" ]]; then
  echo "Missing weights/generated/*.mem — run: make deploy" >&2
  exit 1
fi

echo "Packaging fpga_top → $IP_REPO"
vivado -mode batch -source "$ROOT/board/package_fpga_top.tcl" \
  -tclargs "$ROOT" "$IP_REPO" "$FPGA_PART"
echo "OK: $IP_REPO/component.xml"
