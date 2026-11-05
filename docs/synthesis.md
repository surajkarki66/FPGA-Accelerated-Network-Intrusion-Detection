# Synthesis and Implementation Notes

## 1. Purpose

Vendor-tool configuration, pre-bitstream checks, and resource trade-offs for
the FNN accelerator on **Zynq UltraScale+ (ZCU104)**. Complements
[zcu104_bringup.md](zcu104_bringup.md) and [architecture.md](architecture.md).

## 2. Vivado flow (ZCU104)

1. Add sources under `rtl/accel/` and `rtl/peripheral/`.
2. Add `rtl/include` as a Verilog include directory.
3. Provide `weights/generated/weights.mem` and `biases.mem`; ensure
   `fnn_top` `W_MEM_FILE` / `BIAS_MEM_FILE` resolve at synthesis.
4. Package `fnn_top` + `axi4lite_slave` as AXI4-Lite IP and integrate in a
   Block Design. Address ports are 32-bit; decode uses `[7:0]`.
5. Clock and reset come from the PS (`pl_clk0`, `pl_resetn0`)—not from a
   standalone board pin constraint file.

Full PS, address map, bitstream, and SD bring-up:
[zcu104_bringup.md](zcu104_bringup.md).

## 3. Pre-bitstream checklist

1. **Simulation.** `make sim` (or `make ci-smoke`) passes with the ROMs to
   embed ([simulation.md](simulation.md)).
2. **Parameters.** `fnn_params.vh` matches the trained topology
   (`make deploy` after `--layers` changes).
3. **ROM paths.** `W_MEM_FILE` / `BIAS_MEM_FILE` resolve correctly.
4. **Block Design.** PS 100 MHz `pl_clk0`, reset, AXI master to FNN slave;
   base address recorded ([host.md](host.md)).
5. **On-board bench.** After SD boot, `make board-run`
   ([zcu104_bringup.md](zcu104_bringup.md)).

## 4. Resource and performance knobs

| Parameter / choice | Effect |
| ------------------ | ------ |
| `FNN_NUM_PE` | More MAC lanes: higher DSP/LUT use, lower latency per tile |
| Layer widths (`--layers`) | BRAM depth, address width, iterations; always `make deploy` |
| `FNN_DATA_W` | Keep 8 for the supported Q1.7 export path |
| PL clock | Higher frequency lowers wall-clock latency; 100 MHz is the documented bring-up default |

Memories are sized exactly (`FNN_W_DEPTH`, `FNN_B_DEPTH`).

## 5. Post-implementation check

Timing closure is not a functional proof. Minimum test: load golden sample 0
via MMIO; compare `PRED` to `sim/golden/expected.mem`; then scale sample
count. Pre-silicon gates remain `make lint` and `make sim`.
