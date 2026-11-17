# Host Software Interface (AXI4-Lite MMIO)

This section describes how software running on the Processing System (PS) communicates with the FNN accelerator through the AXI4-Lite memory-mapped interface.

The accelerator provides a set of registers that allow the host software to load input features, start an inference, check its execution status, and retrieve the prediction and execution time.

**Simulation and hardware verification:** The Icarus Verilog testbench communicates with `fnn_top` directly through its feature input ports. Therefore, it does not test the AXI4-Lite interface. The AXI interface is verified on the ZCU104 board using Linux and the [`board/fnn_bench.py`](../board/fnn_bench.py) script.

## 2. Bus and Addressing

The FNN accelerator uses the AXI4-Lite protocol to exchange data and control information with the host processor.

| Property                   | Value                             |
| -------------------------- | --------------------------------- |
| Bus protocol               | AXI4-Lite                         |
| Data width                 | 32 bits                           |
| Address width              | 32 bits                           |
| Register address decoding  | `AWADDR[7:0]` / `ARADDR[7:0]` |
| Recommended address window | At least 4 KiB                    |

Each register is accessed using its offset from the accelerator's base address:
Address =  BASE  + Offset

The base address (`BASE`) is assigned in Vivado's Address Editor. In the current ZCU104 block design, the AXI slave is mapped to **`0x400000000`** through the 40-bit HPM address space.

The register offsets are defined in `rtl/include/fnn_params.vh` and are also used by the Linux benchmark script. The base address is configured through `FNN_BASE_ADDR` in `board/config.env`.

## 3. Register Map

The host software communicates with the accelerator using the following registers.

| Offset   | Register | Access     | Description                                                                                                            |
| -------- | -------- | ---------- | ---------------------------------------------------------------------------------------------------------------------- |
| `0x00` | CTRL     | Write      | Writing `1` to bit 0 starts an inference. This generates a start pulse. Other bits are ignored.                      |
| `0x04` | STATUS   | Read       | Reports the accelerator status. Bit 0 indicates completion, and bit 1 indicates whether the accelerator is busy.       |
| `0x08` | FEAT_W   | Reserved   | Not implemented in the current design. Do not use this register.                                                       |
| `0x0C` | ADDR     | Write      | Selects the feature index for loading input data or reading output scores.                                             |
| `0x10` | DATA     | Read/Write | Used to write input features or read output scores. Input features are stored as INT8 Q1.7 values in the lower 8 bits. |
| `0x14` | PRED     | Read       | Returns the predicted class ID (0 or 1 in the default binary classification configuration).                            |
| `0x18` | CYCLES   | Read       | Returns the number of clock cycles taken by the most recent inference.                                                 |

### STATUS Register

The `STATUS` register provides information about the current state of the accelerator.

| Bit | Name | Description                                                                                    |
| --- | ---- | ---------------------------------------------------------------------------------------------- |
| 0   | DONE | Set when an inference has completed. This bit remains set until the next inference is started. |
| 1   | BUSY | Set while the accelerator is processing an inference.                                          |

Software can read this register to determine when the accelerator has finished processing an input sample.

## 4. Running an Inference

An inference consists of three main steps:

1. Load the input features into the accelerator.
2. Start the inference and wait for completion.
3. Read the predicted class and, optionally, the execution cycle count.

The accelerator accepts 10 input features. Each feature is written separately using the `ADDR` and `DATA` registers.

The following pseudocode illustrates the complete procedure:

```text
# Step 1: Load the input features
for i ← 0 to 9:
    write(BASE + ADDR, i)
    write(BASE + DATA, feature[i])  # Use the lower 8 bits

# Step 2: Start inference
write(BASE + CTRL, 1)

# Step 3: Wait until inference completes
while (read(BASE + STATUS) & 0x01) == 0:
    continue

# Step 4: Read the prediction
pred ← read(BASE + PRED) & 0xFF

# Step 5: Read execution time (optional)
cycles ← read(BASE + CYCLES)
```

The predicted class can then be compared with the expected result for the same input sample.

For verification, the input features are stored in `sim/golden/features.mem`, and their corresponding expected predictions are stored in `sim/golden/expected.mem`.

## 5. Current Limitations
The current hardware interface has the following limitations:
- No dedicated feature-width register: FEAT_W (0x08) is reserved and is not implemented. Input features must be loaded using the ADDR and DATA registers.
- Fixed feature-loading mechanism: Input features are written one at a time rather than transferred as a complete data block.
- No live packet interface: The accelerator currently supports register-based input loading and result retrieval. Live packet input and streaming I/O are outside the scope of this implementation.
- AXI simulation coverage: The Icarus testbench verifies the FNN computation through direct feature ports but does not verify the AXI4-Lite register interface. Hardware verification is performed on the ZCU104 using the Linux benchmark.