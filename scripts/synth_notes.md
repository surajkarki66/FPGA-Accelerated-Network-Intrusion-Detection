# Synthesis notes

## Tools

- **Xilinx / AMD**: Vivado — add `rtl/accel/*.v`, `rtl/peripheral/*.v`, set top `fpga_top`,
  include `rtl/include` as Verilog include dir, set `weights/*.mem` as memory init files.
- **Intel**: Quartus — similar; convert constraints from `constraints/board.xdc.example`.

## Checklist before bitstream

1. `scripts/sim.sh` passes with your exported weights.
2. Update `fnn_params.vh` dims to match the trained model (`make deploy`).
3. Point `fnn_top` `W_MEM_FILE` / `BIAS_MEM_FILE` at `weights/generated/*.mem`.
4. Adapt `constraints/board.xdc.example` to your board clock/reset.
5. For Zynq: package `axi4lite_slave`+`fnn_top` as IP, connect to PS AXI GP port.
6. For Artix-only boards: add a UART feature loader (pattern from mjao1) instead of AXI.

## Resource knobs

| Knob | Effect |
|------|--------|
| `FNN_NUM_PE` | More DSP/LUT, lower latency |
| Layer widths | BRAM depth / address width |
| `FNN_DATA_W` | Accuracy vs area (keep 8 for INT8 path) |
