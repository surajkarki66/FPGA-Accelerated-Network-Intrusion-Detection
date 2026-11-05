# ZCU104 Implementation and Bring-Up Procedure

End-to-end guide for implementing the INT8 FNN accelerator on the **AMD Zynq
UltraScale+ MPSoC ZCU104** and verifying it against the software golden
reference under Linux. Validated result:
**`PASS (82332/82332)`** (~484 cycles ≈ 4.84 µs at 100 MHz).

**Automated path (preferred):** `make board-bd` → `make board-bitstream` →
`make board-boot` → `./board/flash_sd.sh` → `make board-run`.  
Script details: [`../board/README.md`](../board/README.md).

Companion docs: [architecture.md](architecture.md), [simulation.md](simulation.md),
[host.md](host.md), [synthesis.md](synthesis.md), [../board/README.md](../board/README.md).

| Item | Value |
| ---- | ----- |
| Device / board part | `xczu7ev-ffvc1156-2-e` / `xilinx.com:zcu104:part0:1.1` |
| Tooling (validated) | Vivado **2024.2** + PetaLinux SD image **2024.2** |
| PL clock | 100 MHz (`pl_clk0`) |
| Host interconnect | AXI4-Lite MMIO |
| FNN AXI base (this BD) | **`0x400000000`** (40-bit HPM1 aperture) |
| On-board bench | Linux + `/dev/mem` + `board/fnn_bench.py` |

```mermaid
flowchart LR
  SIM[make sim PASS] --> PKG[package fpga_top IP]
  PKG --> BD[Block Design + wrapper]
  BD --> BIT[bitstream]
  BIT --> BOOT[BOOT.BIN + SD flash]
  BOOT --> SSH[Ethernet SSH]
  SSH --> BENCH[fnn_bench.py]
  BENCH --> PASS[PASS accuracy + latency]
```

There are **two ways** to reach a bitstream:

1. **Scripted (recommended for reproducibility)** — `make board-bd` then
   `make board-bitstream`.
2. **GUI (what you can do once by hand)** — package IP, assemble the BD in
   Vivado, then use the same bitstream / SD scripts.

Both end at the same topology and the same `FNN_BASE_ADDR`.

---

## 1. Repository prerequisites

On the build PC, from the repo root:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
make train && make deploy          # weights/generated/*.mem + fnn_params.vh
make golden && make sim            # must PASS before trusting a bitstream
```

The bitstream embeds the same `weights/generated/{weights,biases}.mem` images
that `make sim` used. A failing simulation predicts a failing on-board comparison.

Confirm AXI port widths on `fpga_top` / `axi4lite_slave`: **`AWADDR` / `ARADDR`
are 32 bits**, with register decode on bits `[7:0]` only.

---

## 2. One-time board / tool setup

### 2.1 Tools

```bash
source /tools/Xilinx/Vivado/2024.2/settings64.sh   # also provides bootgen
# need: vivado, bootgen, sshpass, sudo for SD write
```

### 2.2 Board config

```bash
cp board/config.env.example board/config.env
# edit at least: VIVADO_PROJ, IP_REPO, FW_DIR, WIC_IMG, SD_DEV, BOARD_HOST
```

Important variables:

| Variable | Role |
| -------- | ---- |
| `VIVADO_PROJ` / `VIVADO_XPR` | Vivado project directory / `.xpr` |
| `IP_REPO` | Packaged `fpga_top` IP (default `board/out/ip_repo`) |
| `BITSTREAM` | Output `.bit` path |
| `FNN_BASE_ADDR` | Must match Address Editor (**`0x400000000`**) |
| `PL_CLK_MHZ` | Used by `fnn_bench.py` to convert cycles → µs (100) |
| `FW_DIR` | Prebuilt FSBL / PMUFW / ATF / U-Boot for `BOOT.BIN` |
| `WIC_IMG` | Decompressed PetaLinux ZCU104 `.wic` |
| `SD_DEV` | SD block device on the build PC (e.g. `/dev/mmcblk0`) |
| `BOARD_HOST` | Board IP after Ethernet comes up |

### 2.3 Prebuilt firmware (for `BOOT.BIN`)

```bash
git clone --depth 1 -b xilinx_v2024.2 \
  https://github.com/Xilinx/soc-prebuilt-firmware.git \
  /path/to/zcu104_linux/soc-prebuilt-firmware
# set FW_DIR=.../soc-prebuilt-firmware/zcu104-zynqmp
```

### 2.4 PetaLinux SD image

1. Download the **2024.2** ZCU104 SD image (`.wic.xz`) from AMD’s PetaLinux
   release area (Yocto Native BSP / ZCU104).
2. Decompress to a `.wic` and set `WIC_IMG` in `config.env`.

This flow boots **Linux from µSD** and does **not** require JTAG for the
accuracy bench.

---

## 3. Package `fpga_top` as AXI4-Lite IP

The Block Design instantiates a packaged IP (`user.org:user:fpga_top:1.0`),
not loose RTL files.

### 3.1 Scripted

```bash
make board-package
# → $IP_REPO/component.xml + src/*.v, fnn_params.vh, weights.mem, biases.mem
```

What the script does:

1. Copies `rtl/accel/*`, `rtl/peripheral/*`, `rtl/include/fnn_params.vh`, and
   `weights/generated/*.mem` into the IP `src/` tree.
2. Points `fnn_top` `W_MEM_FILE` / `BIAS_MEM_FILE` at the packaged `.mem` paths.
3. Declares slave bus `interface_aximm` (AXI4-Lite), clock `clk`, active-low
   `rst_n`, and a **64 KiB** memory map (`reg0`) for the Address Editor.

### 3.2 GUI equivalent (optional)

1. **Tools → Create and Package New IP**.
2. Add the same sources as above; top = `fpga_top`.
3. Map AXI ports to an AXI4-Lite slave interface named `interface_aximm`.
4. Associate that interface with `clk`; set `rst_n` polarity **ACTIVE_LOW**.
5. Add a memory map / address block (≥ 4 KiB; this project uses 64 KiB).
6. Package and note the repository path → set `IP_REPO` in `config.env`.

---

## 4. Create the Vivado project and Block Design

### 4.1 Scripted (preferred)

```bash
make board-bd
# packages IP (unless SKIP_PACKAGE=1), then create_bd.tcl → $VIVADO_XPR
```

`board/create_bd.tcl` builds exactly this topology:

```text
zynq_ultra_ps_e_0
  M_AXI_HPM0_FPD ──┐
  M_AXI_HPM1_FPD ──┼──► axi_smc (SmartConnect) ──► fpga_top_0 / interface_aximm
  pl_clk0 (100 MHz) ──► fpga_top.clk, smc, maxihpm*_aclk, proc_sys_reset
  pl_resetn0 ──► rst_ps8_0_100M ──► peripheral_aresetn → fpga_top.rst_n, smc.aresetn

Address Editor (PS Data):
  SEG_fpga_top_0_reg0  offset = 0x400000000   range = 64K
```

**Why both HPM0 and HPM1?**  
`0xA0000000` sits on the HPM0 aperture. The working Linux map uses
**`0x400000000`**, which is a **40-bit HPM1** aperture. Enabling only HPM0 and
probing `0xA0000000` from Linux caused hangs; HPM0+HPM1 with base
`0x400000000` is the combination that passed.

Top of the project after the script: **`fnn_bd_wrapper`**.

### 4.2 GUI steps (same topology, by hand)

Use this if you prefer clicking once; the scripted path above reproduces it.

#### 4.2.1 Project

1. Vivado → **Create Project** → RTL project.
2. Board: **Zynq UltraScale+ ZCU104 Evaluation Board**
   (`xilinx.com:zcu104:part0:1.1`).
3. **Settings → IP → Repository** → add `$IP_REPO` → **Apply**.

#### 4.2.2 Block Design

1. **Create Block Design**, name e.g. `fnn_bd`.
2. Add **Zynq UltraScale+ MPSoC**. Run **Run Block Automation** with
   **Apply Board Preset** enabled (DDR, UART, Ethernet, SD, clocks).
3. Re-customise the PS (double-click):
   - **PS-PL Configuration → AXI HPM0 FPD** = enabled  
   - **AXI HPM1 FPD** = enabled (required for `0x4_0000_0000`)
   - **Clock Configuration → Output Clocks → PL Fabric Clocks → `pl_clk0`**
     = **100 MHz**
4. Add IP **`fpga_top`** (from your repo).
5. **Run Connection Automation**:
   - Connect `fpga_top` AXI slave to **M_AXI_HPM0_FPD** via a new
     **AXI SmartConnect**.
   - Clock / reset automation should attach `pl_clk0` and a
     **Processor System Reset** (`peripheral_aresetn` → `rst_n`).
6. Also connect **M_AXI_HPM1_FPD** to the **same** SmartConnect (second
   slave port on the interconnect).
7. Open **Address Editor**:
   - Assign `fpga_top` / `reg0` in the PS **Data** space.
   - Set **Offset = `0x400000000`**, **Range = 64K**.
   - Do **not** leave it at the default `0xA0000000` if you will use the
     Linux bench as shipped (`FNN_BASE_ADDR=0x400000000`).
8. **Validate Design** (should be clean aside from benign PS clock notes).
9. **Create HDL Wrapper** → let Vivado manage wrapper → set
   `fnn_bd_wrapper` as top.

Optional: leave `dbg_busy` / `dbg_done` / `dbg_pred` unconnected; they are
not required for the Linux bench.

### 4.3 Timing / resources

The default net (`10 → 6 → 1`, four MAC lanes) is light on the ZU7EV. If a
deeper net fails timing: lower `pl_clk0`, or reduce `FNN_NUM_PE` and re-run
`make deploy`. See [synthesis.md](synthesis.md).

---

## 5. Generate the bitstream

### 5.1 Scripted (clears stale IP cache)

After **any** RTL change to the packaged IP (especially `axi4lite_slave`),
always rebuild this way. Vivado otherwise reuses an Out-of-Context DCP and
your edit never reaches the bitstream.

```bash
make board-bitstream
# board/build_bitstream.sh → board/build_bitstream.tcl
#   • patches axi4lite_slave.v into the BD ipshared copy
#   • points IP cache at a fresh empty directory
#   • resets OOC synth for fpga_top, then synth → impl → write_bitstream
#   • copies fnn_bd_wrapper.bit → $BITSTREAM
```

### 5.2 GUI

1. **Generate Bitstream** (synth + impl).
2. If you edited packaged IP sources: **IP Status → Upgrade**, or delete the
   IP cache / reset the `fnn_bd_fpga_top_*_synth_1` run before regenerating.
3. Copy the generated `.bit` to the path in `BITSTREAM`, or set `BITSTREAM` to
   the run output under `*.runs/impl_1/`.

### 5.3 Known RTL pitfall (AXI write)

Early bring-up hung on feature writes because the AXI4-Lite slave could
accept `AW` and `W` on different cycles without holding `AWADDR`. The fixed
slave registers the address when `AWVALID && AWREADY` and only commits the
write when both address and data are present. If you reintroduce a
combinational `AWADDR` decode gated only on `WVALID`, MMIO writes break
again — and a **stale IP cache** can hide the fix until you use
`build_bitstream.sh`.

---

## 6. Build `BOOT.BIN` and flash the SD card

Linux must load **your** PL bitstream at boot. The scripts take a stock
PetaLinux WIC and replace / overlay boot firmware with one that includes
the FNN `.bit`.

### 6.1 Assemble `BOOT.BIN`

```bash
make board-boot
# bootgen: FSBL + PMUFW + $BITSTREAM + ATF + DTB + U-Boot
# → board/out/BOOT.BIN
```

Requires `FW_DIR` (Section 2.3) and a successful `$BITSTREAM`.

### 6.2 Flash µSD on the build PC

1. Insert the SD card; note the block device (`lsblk`) → set `SD_DEV`.
2. Unmount any automounted partitions.
3. Run (writes the WIC, then overlays `BOOT.BIN` and enables root SSH):

```bash
./board/flash_sd.sh          # needs sudo
```

What it does, in order:

1. `dd` / write `WIC_IMG` onto `SD_DEV`.
2. Mount the boot partition; install `board/out/BOOT.BIN`.
3. Patch rootfs via `enable_ssh.sh`: root login over SSH, password `fnn`,
   optional static IP on `end0` (override with `FNN_ETH_IP`).

### 6.3 Board switches and first boot

1. Insert the SD into the ZCU104.
2. Boot mode **SW6 = ON OFF OFF OFF** (SD boot; confirm against your board’s
   silkscreen / UG if unsure).
3. Connect **Ethernet** (RJ45 to your LAN) and **UART** (optional debug).
4. Power on.

Default after `flash_sd.sh`:

| Item | Value |
| ---- | ----- |
| User / password | `root` / `fnn` |
| Static IP attempt | `192.168.178.10` on `end0` |
| DHCP hostname | often `zynqmp-zcu104-sdt-full` |

If DHCP wins, find the board on the LAN and set `BOARD_HOST` in `config.env`
(this bring-up used e.g. `192.168.178.183`).

```bash
ssh root@$BOARD_HOST     # password: fnn
```

---

## 7. On-board accuracy and latency bench

From the **build PC** (repo root, `config.env` loaded by the script):

```bash
make board-run
# pack_golden.py → features.bin / expected.bin
# scp to board → run fnn_bench.py over SSH
```

`fnn_bench.py` (runs **on the board**):

1. `mmap` `/dev/mem` at `FNN_BASE_ADDR`.
2. For each golden vector: write 10× INT8 features via `ADDR`/`DATA`, pulse
   `CTRL`, poll `STATUS`, read `PRED` and `CYCLES`.
3. Compare `PRED` to `expected.bin` (software INT8 golden — **not** UNSW
   labels).
4. Print accuracy, mean/min/max latency (cycles and µs at `PL_CLK_MHZ`), and
   host-loop throughput.

Expected success line:

```text
PASS (82332/82332)
```

with average cycles near **484** → **~4.84 µs** at 100 MHz.

Optional: reload PL without reflashing the SD:

```bash
RELOAD_BIT=1 board/run_on_board.sh
```

MMIO register map: [host.md](host.md).

---

## 8. Day-to-day rebuild cheat sheet

| Change | What to run |
| ------ | ----------- |
| Weights / topology (`make deploy`) | `make board-package` → `make board-bitstream` → `make board-boot` → flash or `RELOAD_BIT=1` |
| AXI / accelerator RTL only | `make board-bitstream` (cache cleared) → boot or reload |
| BD / address map | `make board-bd` then bitstream |
| First bring-up from clone | Sections 1 → 2 → `make board-bd` → bitstream → boot → flash → `make board-run` |

Full scripted chain after `config.env` exists:

```bash
make deploy && make golden && make sim
make board-bd
make board-bitstream
make board-boot
./board/flash_sd.sh
# power board, set BOARD_HOST
make board-run
```

---

## 9. Interpreting failures

| Symptom | Likely cause | What to check |
| ------- | ------------ | ------------- |
| `PASS (N/N)` | Healthy | Record cycles / µs |
| Wrong `pred` vs golden | Stale `.mem` / bitstream, or RTL bug | Re-`deploy`, re-package, rebuild with cache clear; re-sim |
| `TIMEOUT` waiting for `done` | Clock/reset not reaching IP, or slave not mapped | BD clocks/resets; `FNN_BASE_ADDR` |
| Bus hang / machine check on MMIO | **Wrong base** (e.g. `0xA0000000` when BD has `0x400000000`) | Address Editor vs `config.env` / `fnn_bench.py --base` |
| Writes ignored / garbage features | AXI AW/W race or **stale IP DCP** | Fixed `axi4lite_slave`; always use `build_bitstream.sh` after IP edits |
| SSH unreachable | Network / image | UART log; `end0` up; DHCP vs static; password `fnn` |
| Bitstream loads but old behaviour | IP cache | `make board-bitstream` (forces empty cache) |

Acceptance is **identity with the software INT8 golden** (`sim/golden`), not
agreement with UNSW dataset labels.

---

## 10. Subsequent work

1. Live traffic: PS (or PL) must still emit the same ten RFE-selected Q1.7
   features before invoking this IP.
2. Optional Linux driver (UIO / character device) instead of `/dev/mem`.

---

## 11. Acceptance checklist

- [ ] `make sim` passes with the ROM images intended for the bitstream
- [ ] `make board-package` (or GUI package) produces `user.org:user:fpga_top:1.0`
- [ ] BD: 100 MHz `pl_clk0`, proc reset, **HPM0 + HPM1**, SmartConnect → `fpga_top`
- [ ] Address Editor: **`0x400000000` / 64K** recorded as `FNN_BASE_ADDR`
- [ ] `make board-bitstream` completes; `$BITSTREAM` exists
- [ ] `make board-boot` → `board/out/BOOT.BIN`; SD flashed; SW6 = SD boot
- [ ] SSH as `root` / `fnn` works; `BOARD_HOST` set
- [ ] `make board-run` reports `PASS` with ~484 cycles @ 100 MHz
