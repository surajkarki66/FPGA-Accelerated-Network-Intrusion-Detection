# Simulation and Verification Methodology

## 1. Objectives

RTL simulation in this repository serves two complementary purposes:

1. **Unit verification** of the Q1.7 multiply–accumulate (MAC) contract on a
   single processing element.
2. **System-level bit-accuracy checking** of the full accelerator (`fnn_top`)
   against a software INT8 reference model over a large set of feature
   vectors (golden vectors).

A successful simulation campaign establishes that, for identical weights,
biases, and input features, the hardware prediction matches the software
INT8 forward pass. It does **not**, by itself, certify classification quality
relative to UNSW-NB15 ground-truth labels, although label accuracy is
reported as a diagnostic statistic.

Simulation is performed with **Icarus Verilog** (`iverilog` / `vvp`). Static
lint of the board top is available separately via Verilator (`make lint`).

## 2. Prerequisites and invocation

```bash
make deploy          # export ROMs + fnn_params.vh
make golden          # write sim/golden/ (requires UNSW CSVs for full set)
make sim             # regenerates golden, then runs scripts/sim.sh
```

`make sim` depends on `golden`. Continuous-integration environments without
the UNSW CSVs may instead run:

```bash
make ci-smoke        # synthetic ROMs + 50 random vectors, then sim.sh
```

Tooling requirements: a POSIX shell, Python dependencies from
`requirements.txt`, and Icarus Verilog on `PATH`.

## 3. Compilation flow

[`scripts/sim.sh`](../scripts/sim.sh) executes two independent elaborations:

| Order | Testbench | Design under test | Include paths |
| ----- | --------- | ----------------- | ------------- |
| 1 | `sim/tb_mac_unit.v` | `rtl/accel/mac_unit.v` | `rtl/include` |
| 2 | `sim/tb_fnn_top.v` | All of `rtl/accel/*.v` listed in the script | `rtl/include`, repository root |

Neither elaboration includes `fpga_top` nor `axi4lite_slave`. Host MMIO
behaviour is therefore verified on hardware (or would require a separate AXI
bus-functional model not shipped in this revision).

Both benches use a `#5` half-period clock, i.e. a **10 ns** period
(**100 MHz**). This frequency is a simulation convenience chosen to match the
recommended programmable-logic clock in the ZCU104 bring-up guide; it is not
a timing closure claim.

## 4. Unit test: `tb_mac_unit`

### 4.1 Stimulus

After reset and accumulator clear, the bench applies:

- two successive products \(2 \times 3\) under `valid_in`;
- a bias of \(1\) under `bias_add`;
- a `finalize` pulse.

### 4.2 Expected result

\[
\mathrm{acc} = 2\cdot 3 + 2\cdot 3 + (1 \ll 7) = 140, \qquad
y = 140 \gg 7 = 1.
\]

Any deviation from \(y = 1\) or a missing `valid_out` terminates the
simulation with failure. A Value Change Dump (`sim/tb_mac_unit.vcd`) is
written for waveform inspection.

This test isolates fixed-point alignment and saturation from memory and
scheduling complexity.

## 5. Golden-vector generation

### 5.1 Full UNSW path (`make golden`)

[`sw/generate_test_vectors.py`](../sw/generate_test_vectors.py) performs the
following steps:

1. Load `weights.mem` and `biases.mem` from `weights/generated/` (or a
   user-specified directory) and reshape them according to
   `export_meta.txt` / layer sizes.
2. Load the UNSW-NB15 **test** partition through the same preprocessing
   pipeline used at training time.
3. Convert each feature row to Q1.7 (`to_q17`).
4. Execute `sw_int_forward` (software mirror of the FPGA datapath).
5. Emit artefacts under `sim/golden/`.

| Artefact | Description |
| -------- | ----------- |
| `features.mem` | Flattened INT8 features, `input_dim` hexadecimal bytes per sample |
| `expected.mem` | Software INT8 class prediction, one byte per sample |
| `labels.mem` | Ground-truth UNSW label (`0`/`1` for the binary task) |
| `golden_params.vh` | `` `GOLDEN_N_SAMPLES` `` and `` `GOLDEN_FEAT_WORDS` `` for the testbench |
| `meta.txt` / `expected.txt` | Human-readable summary statistics |

By default the **entire** test set is exported. A `--limit N` argument may
restrict the count for shorter runs.

### 5.2 Continuous-integration path (`make ci-smoke`)

[`scripts/ci_smoke_export.py`](../scripts/ci_smoke_export.py) synthesises a
small random INT8 network and fifty random feature vectors, writes ROMs and
golden files, and then invokes the same `sim.sh`. Labels in this mode are
synthetic and must not be interpreted as detection accuracy.

### 5.3 Software reference semantics

`sw_int_forward` mirrors the hardware recurrence for each layer: matrix–vector
products in INT32, bias left-shifted by seven bits, arithmetic right shift,
saturation to INT8, and ReLU on all but the final layer. Binary networks
threshold the scalar score at zero; multi-class networks take the argmax.

## 6. System test: `tb_fnn_top`

### 6.1 Design under test configuration

The bench instantiates `fnn_top` with:

```verilog
.W_MEM_FILE("weights/generated/weights.mem"),
.BIAS_MEM_FILE("weights/generated/biases.mem")
```

Activation memory is loaded through the `feat_we` / `feat_addr` / `feat_wdata`
ports—the same programming model the AXI slave ultimately drives on the
board.

### 6.2 Per-sample procedure

For each golden sample \(s = 0 \ldots N-1\):

1. Write `FNN_INPUT_DIM` feature bytes into activation memory.
2. Pulse `start` for one cycle.
3. Wait until `done` is asserted.
4. Compare `pred` with `expected[s]` (**hard pass/fail criterion**).
5. Optionally tally agreement with `labels[s]` (**accuracy diagnostic**).
6. Accumulate cycle-count statistics from `cycle_count`.

Waveform dumping is deliberately omitted for full-corpus runs because the
resulting VCD would be impractically large. A long wall-clock timeout guards
against deadlock.

### 6.3 Reported metrics

On completion the bench prints:

- hardware versus software INT8 match count;
- hardware versus true-label accuracy;
- minimum, average, and maximum cycles per sample;
- estimated latency and throughput at the simulated 100 MHz clock
  (compute only; host MMIO overhead is excluded).

The simulation **fails** if any sample disagrees with the software INT8
prediction. Label accuracy may be strictly less than 100% while the run still
passes.

## 7. Interpretation of results

| Outcome | Interpretation |
| ------- | -------------- |
| `tb_mac_unit` PASS | Single-lane Q1.7 MAC contract holds for the hand-crafted case |
| `tb_fnn_top` PASS | Accelerator + ROMs are bit-accurate w.r.t. `sw_int_forward` on all golden inputs |
| `tb_fnn_top` FAIL | Scheduling, memory init, parameter mismatch, or arithmetic divergence |
| High label accuracy | Desirable for the intrusion-detection application, but orthogonal to RTL correctness |

After a topology or quantisation change, always re-run `make deploy`,
`make golden`, and `make sim` before synthesising a bitstream that embeds the
new ROMs.

## 8. Relationship to on-board testing

On the ZCU104, `make board-run` replays the **full** golden set through the
AXI map via `board/fnn_bench.py` and compares every `PRED` to
`sim/golden/expected.mem`. That is the practical bridge from this document to
[`zcu104_bringup.md`](zcu104_bringup.md) (validated: `PASS` on all samples).
