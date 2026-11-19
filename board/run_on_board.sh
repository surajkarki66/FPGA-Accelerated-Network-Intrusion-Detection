#!/usr/bin/env bash
# Pack goldens, copy bench + data to the board, run accuracy/latency test over SSH.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/board/lib.sh"
load_config

echo "Packing golden vectors..."
python3 "$ROOT/board/pack_golden.py" --repo "$ROOT" --out "$OUT_DIR/golden"

FEAT="$OUT_DIR/golden/features.bin"
EXP="$OUT_DIR/golden/expected.bin"
[[ -f "$FEAT" && -f "$EXP" ]] || exit 1

echo "Uploading to ${BOARD_USER}@${BOARD_HOST}..."
scp_board \
  "$ROOT/board/fnn_bench.py" \
  "$FEAT" \
  "$EXP" \
  "${BOARD_USER}@${BOARD_HOST}:/tmp/"

# Optional: push bitstream and reload PL without reboot
if [[ "${RELOAD_BIT:-0}" == "1" && -f "$BITSTREAM" ]]; then
  echo "Reloading PL bitstream on board..."
  scp_board "$BITSTREAM" "${BOARD_USER}@${BOARD_HOST}:/tmp/fnn_bd_wrapper.bit"
  ssh_board 'cp /tmp/fnn_bd_wrapper.bit /lib/firmware/fnn_bd_wrapper.bit &&
    echo fnn_bd_wrapper.bit > /sys/class/fpga_manager/fpga0/firmware &&
    cat /sys/class/fpga_manager/fpga0/state'
fi

echo "Running bench..."
# shellcheck disable=SC2029
ssh_board "FNN_BASE_ADDR=$FNN_BASE_ADDR PL_CLK_MHZ=$PL_CLK_MHZ \
  python3 -u /tmp/fnn_bench.py \
    --features /tmp/features.bin \
    --expected /tmp/expected.bin \
    --base $FNN_BASE_ADDR \
    --clk-mhz $PL_CLK_MHZ \
    --report-every ${REPORT_EVERY:-10000}"
