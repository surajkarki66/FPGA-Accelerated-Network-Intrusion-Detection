#!/usr/bin/env bash
# Rebuild the FNN bitstream 
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"  # clears Vivado IP cache so RTL edits take effect
# shellcheck disable=SC1091
source "$ROOT/board/lib.sh"
load_config
need_cmd vivado

echo "Building bitstream → $BITSTREAM"
# Capture mtime so we can detect a failed run that left an old .bit behind
old_mtime=0
[[ -f "$BITSTREAM" ]] && old_mtime=$(stat -c %Y "$BITSTREAM")

vivado -mode batch -source "$ROOT/board/build_bitstream.tcl" \
  -tclargs "$VIVADO_XPR" \
           "$ROOT/rtl/peripheral/axi4lite_slave.v" \
           "$BITSTREAM"
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "ERROR: vivado exited $rc" >&2
  exit "$rc"
fi
if [[ ! -f "$BITSTREAM" ]]; then
  echo "ERROR: bitstream not produced at $BITSTREAM" >&2
  exit 1
fi
new_mtime=$(stat -c %Y "$BITSTREAM")
if [[ "$new_mtime" -le "$old_mtime" ]]; then
  echo "ERROR: $BITSTREAM was not updated (stale file)" >&2
  exit 1
fi
echo "OK: $BITSTREAM"
