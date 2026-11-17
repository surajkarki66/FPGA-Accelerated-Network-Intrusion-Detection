# Simulation and Verification Methodology

RTL simulation in this project serves two complementary purposes:

1. **Unit verification** of the Q1.7 multiply–accumulate (MAC) on a
   single processing element.
2. **System-level bit-accuracy checking** of the accelerator (`fnn_top`)
   against a software INT8 reference model over a large set of feature
   vectors (golden vectors).

It is important to distinguish between hardware correctness and model accuracy. A successful simulation confirms that the hardware correctly implements the software INT8 computation. It does not necessarily mean that the classifier achieves high accuracy on the UNSW-NB15 test labels. Classification accuracy is reported separately as an additional performance metric.

The RTL simulations are performed using **Icarus Verilog** (`iverilog` and `vvp`). Static linting of the FPGA top-level design is also available using Verilator through `make lint`.

## 1. Prerequisites and invocation

```bash
make deploy          # Export ROM files and fnn_params.vh
make golden          # Generate software reference outputs
make sim             # Generate golden vectors and run RTL simulation
```

## 2. Compilation flow

[`scripts/sim.sh`](../scripts/sim.sh) executes two independent elaborations:

| Order | Testbench             | Design under test                             | Include paths                    |
| ----- | --------------------- | --------------------------------------------- | -------------------------------- |
| 1     | `sim/tb_mac_unit.v` | `rtl/accel/mac_unit.v`                      | `rtl/include`                  |
| 2     | `sim/tb_fnn_top.v`  | All of `rtl/accel/*.v` listed in the script | `rtl/include`, repository root |

Host MMIO behaviour is therefore verified on hardware. Both benches use a `#5` half-period clock, i.e. a **10 ns** period (**100 MHz**). This frequency is a simulation convenience chosen to match the recommended programmable-logic clock in the ZCU104.

## 3. Unit test: `tb_mac_unit`

### 3.1 Stimulus

After reset and accumulator clear, the bench applies:

- two successive products $2 \times 3$ under `valid_in`;
- a bias of $1$ under `bias_add`;
- a `finalize` pulse.

### 3.2 Expected result

$$
\begin{aligned}
\mathrm{acc} &= 2\cdot 3 + 2\cdot 3 + (1 \ll 7) = 140, \\
y &= 140 \gg 7 = 1.
\end{aligned}
$$

Any deviation from $y = 1$ or a missing `valid_out` terminates the simulation with failure. A Value Change Dump (`sim/tb_mac_unit.vcd`) is
written for waveform inspection. This test isolates fixed-point alignment and saturation from memory and scheduling complexity.

## 4. Golden-vector generation

### 4.1 Full UNSW path (`make golden`)

[`sw/generate_test_vectors.py`](../sw/generate_test_vectors.py) performs the following steps:

1. Load `weights.mem` and `biases.mem` from `weights/generated/` (or a user-specified directory) and reshape them according to `export_meta.txt` / layer sizes.
2. Load the UNSW-NB15 **test** partition through the same preprocessing pipeline used at training time.
3. Convert each feature row to Q1.7 (`to_q17`).
4. Execute `sw_int_forward` (software mirror of the FPGA datapath).
5. Emit artefacts under `sim/golden/`.

| Artefact                       | Description                                                              |
| ------------------------------ | ------------------------------------------------------------------------ |
| `features.mem`               | Flattened INT8 features, `input_dim` hexadecimal bytes per sample      |
| `expected.mem`               | Software INT8 class prediction, one byte per sample                      |
| `labels.mem`                 | Ground-truth UNSW label (`0`/`1` for the binary task)                |
| `golden_params.vh`           | `` `GOLDEN_N_SAMPLES` `` and `` `GOLDEN_FEAT_WORDS` `` for the testbench |
| `meta.txt`, `expected.txt` | Human-readable summary statistics                                        |

By default the **entire** test set is exported. A `--limit N` argument may restrict the count for shorter runs.

### 4.2 Continuous-integration path (`make ci-smoke`)

[`scripts/ci_smoke_export.py`](../scripts/ci_smoke_export.py) synthesises a small random INT8 network and fifty random feature vectors, writes ROMs and golden files, and then invokes the same `sim.sh`. Labels in this mode are synthetic and must not be interpreted as detection accuracy.

### 4.3 Software reference semantics

`sw_int_forward` mirrors the hardware recurrence for each layer: matrix–vector products in INT32, bias left-shifted by seven bits, arithmetic right shift, saturation to INT8, and ReLU on all but the final layer. Binary networks threshold the scalar score at zero and multi-class networks take the argmax.

## 5. System test: `tb_fnn_top`

### 5.1 Design under test configuration

The bench instantiates `fnn_top` with:

```verilog
.W_MEM_FILE("weights/generated/weights.mem"),
.BIAS_MEM_FILE("weights/generated/biases.mem")
```

Activation memory is loaded through the `feat_we` / `feat_addr` / `feat_wdata` ports, the same programming model the AXI slave ultimately drives on the board.

### 5.2 Per-sample procedure

For each golden sample $s = 0, \ldots, N-1$:

1. Write `FNN_INPUT_DIM` feature bytes into activation memory.
2. Pulse `start` for one cycle.
3. Wait until `done` is asserted.
4. Compare `pred` with `expected[s]` (**hard pass/fail criterion**).
5. Optionally tally agreement with `labels[s]` (**accuracy diagnostic**).
6. Accumulate cycle-count statistics from `cycle_count`.

Waveform dumping is deliberately omitted for full-corpus runs because the resulting VCD would be impractically large. A long wall-clock timeout guards against deadlock.

### 5.3 Reported metrics

On completion the bench prints:

- hardware versus software INT8 match count;
- hardware versus true-label accuracy;
- minimum, average, and maximum cycles per sample;
- estimated latency and throughput at the simulated 100 MHz clock

The simulation **fails** if any sample disagrees with the software INT8 prediction.

## 6. Interpretation of results

| Outcome                | Interpretation                                                                     |
| ---------------------- | ---------------------------------------------------------------------------------- |
| `tb_mac_unit` PASS     | Single-lane Q1.7 MAC contract holds for the hand-crafted case                      |
| `tb_fnn_top` PASS      | Accelerator + ROMs are bit-accurate w.r.t. `sw_int_forward` on all golden inputs   |
| `tb_fnn_top` FAIL      | Scheduling, memory init, parameter mismatch, or arithmetic divergence              |
| High label accuracy    | Desirable for the intrusion-detection application, but orthogonal to RTL correctness |

After a topology or quantization change, always re-run `make deploy`, `make golden`, and `make sim` before synthesising a bitstream that embeds the new ROMs.
