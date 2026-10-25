#!/usr/bin/env bash
# Run Icarus Verilog smoke tests from repo root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

INC="-I rtl/include"
RTL_ACCEL=(
  rtl/accel/mac_unit.v
  rtl/accel/relu.v
  rtl/accel/argmax.v
  rtl/accel/act_mem.v
  rtl/accel/weight_mem.v
  rtl/accel/shared_mac_engine.v
  rtl/accel/layer_controller.v
  rtl/accel/fnn_top.v
)

echo "== tb_mac_unit =="
iverilog -g2012 $INC -o sim/tb_mac_unit.vvp sim/tb_mac_unit.v rtl/accel/mac_unit.v
vvp sim/tb_mac_unit.vvp

echo "== tb_fnn_top =="
# Include repo root so `include "sim/golden/golden_params.vh" resolves
iverilog -g2012 $INC -I . -o sim/tb_fnn_top.vvp sim/tb_fnn_top.v "${RTL_ACCEL[@]}"
vvp sim/tb_fnn_top.vvp

echo "All sims OK"
