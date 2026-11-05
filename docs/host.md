# Host Software Interface (AXI MMIO)

## 1. Purpose

Memory-mapped register specification for the FNN accelerator via
`axi4lite_slave`. Icarus simulation drives `fnn_top` through direct feature
ports and does **not** cover this AXI path. On-board verification uses the
same map from Linux via [`board/fnn_bench.py`](../board/fnn_bench.py).

Board scripts: [../board/README.md](../board/README.md).  
Bring-up: [zcu104_bringup.md](zcu104_bringup.md).  
Architecture: [architecture.md](architecture.md).

## 2. Bus and addressing model

| Property | Value |
| -------- | ----- |
| Protocol | AXI4-Lite |
| Data width | 32 bits |
| Address width (port) | 32 bits |
| Register decode | `AWADDR[7:0]` / `ARADDR[7:0]` |
| Recommended window | ≥ 4 KiB in the PS address map |

\[
\mathrm{address} = \mathrm{BASE} + \mathrm{offset}
\]

\(\mathrm{BASE}\) comes from the Vivado Address Editor. This project’s ZCU104
BD maps the slave at **`0x400000000`** (40-bit HPM), not `0xA0000000`. Offsets
match `rtl/include/fnn_params.vh` and the constants in `board/fnn_bench.py`
(`FNN_BASE_ADDR` in `board/config.env`).

## 3. Register map

| Offset | Name | Access | Description |
| ------ | ---- | ------ | ----------- |
| `0x00` | CTRL | W | Bit 0 = 1 pulses `start`. Other bits ignored. |
| `0x04` | STATUS | R | Bit 0: `done` (sticky until next start). Bit 1: `busy`. |
| `0x08` | FEAT_W | — | Reserved; **not** decoded by the slave. Do not use. |
| `0x0C` | ADDR | W | Index for `DATA` (feature load or score read-back). |
| `0x10` | DATA | R/W | Write: INT8 Q1.7 feature at `ADDR`. Read: score at `ADDR`. |
| `0x14` | PRED | R | Class id (binary default: 0/1). |
| `0x18` | CYCLES | R | Cycle count of last inference. |

### STATUS bits

| Bit | Meaning |
| --- | ------- |
| 0 | Inference completed since last start (`DONE`) |
| 1 | Controller busy (`BUSY`) |

## 4. Canonical programming sequence

```text
for i ← 0 to 9:
    write(BASE + ADDR, i)
    write(BASE + DATA, feature[i])   # low 8 bits
write(BASE + CTRL, 1)
poll STATUS until DONE
pred   ← read(BASE + PRED) & 0xFF
cycles ← read(BASE + CYCLES)          # optional
```

`pred` must match `sim/golden/expected.mem` for the same feature vector from
`sim/golden/features.mem`.

## 5. Linux bench (supported path)

```bash
make board-run    # requires board/config.env and a booted ZCU104
```

`fnn_bench.py` `mmap`s `/dev/mem` at `FNN_BASE_ADDR`, runs the sequence above
for every golden sample, and reports accuracy plus latency from `CYCLES` at
`PL_CLK_MHZ`. See [../board/README.md](../board/README.md).

## 6. Limitations

- `FEAT_W` (`0x08`) is unimplemented; use `ADDR`/`DATA`.
- Live packet I/O is out of scope.
