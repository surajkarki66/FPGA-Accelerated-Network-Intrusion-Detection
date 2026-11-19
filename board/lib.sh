# Shared helpers for board/*.sh — source this, do not execute.
BOARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BOARD_DIR/.." && pwd)"

_source_board_config() {
  local cfg="${BOARD_CONFIG:-$BOARD_DIR/config.env}"
  if [[ ! -f "$cfg" ]]; then
    echo "Missing $cfg — copy board/config.env.example to board/config.env" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  set -a
  source "$cfg"
  set +a
}

# Vivado project / IP packaging.
load_config_vivado() {
  _source_board_config
  : "${VIVADO_PROJ:?}"
  : "${VIVADO_XPR:=$VIVADO_PROJ/$(basename "$VIVADO_PROJ").xpr}"
  : "${BITSTREAM:=$VIVADO_PROJ/fnn_bd_wrapper.bit}"
  : "${IP_REPO:=$REPO_ROOT/board/out/ip_repo}"
  : "${BOARD_PART:=xilinx.com:zcu104:part0:1.1}"
  : "${FPGA_PART:=xczu7ev-ffvc1156-2-e}"
  : "${FNN_BASE_ADDR:=0x400000000}"
  : "${PL_CLK_MHZ:=100}"
  OUT_DIR="${OUT_DIR:-$REPO_ROOT/board/out}"
  mkdir -p "$OUT_DIR"
}

# Full board flow (bitstream rebuild, flash, SSH bench).
load_config() {
  load_config_vivado
  : "${FW_DIR:?}"
  : "${WIC_IMG:?}"
  : "${SD_DEV:?}"
  : "${BOARD_HOST:?}"
  : "${BOARD_USER:=root}"
  : "${BOARD_PASS:=fnn}"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

ssh_board() {
  need_cmd sshpass
  sshpass -p "$BOARD_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "${BOARD_USER}@${BOARD_HOST}" "$@"
}

scp_board() {
  need_cmd sshpass
  sshpass -p "$BOARD_PASS" scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$@"
}
