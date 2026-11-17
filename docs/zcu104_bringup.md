# ZCU104 Implementation and Bring-Up Procedure

End-to-end guide for implementing the INT8 FNN accelerator on the **AMD Zynq UltraScale+ MPSoC ZCU104** and verifying it against the software golden reference under Linux. Validated result:**`PASS (82332/82332)`** (~484 cycles ≈ 4.84 µs at 100 MHz).

**Automated path (preferred):** `make board-bd` → `make board-bitstream` → `make board-boot` → `./board/flash_sd.sh` → `make board-run`.

| Item                | Value                                                         |
| ------------------- | ------------------------------------------------------------- |
| Device / board part | `xczu7ev-ffvc1156-2-e` / `xilinx.com:zcu104:part0:1.1`    |
| Tooling (validated) | Vivado **2024.2** + PetaLinux SD image **2024.2** |
| PL clock            | 100 MHz (`pl_clk0`)                                         |
| Host interconnect   | AXI4-Lite MMIO                                                |
| FNN AXI base        | **`0x400000000`** (40-bit HPM1 aperture)              |
| On-board bench      | Linux + `/dev/mem` + `board/fnn_bench.py`                 |

`````mermaid
flowchart LR
  SIM[make sim PASS] --> PKG[package fpga_top IP]
  PKG --> BD[Block Design + wrapper]
  BD --> BIT[bitstream]
  BIT --> BOOT[BOOT.BIN + SD flash]
  BOOT --> SSH[Ethernet SSH]
  SSH --> BENCH[fnn_bench.py]
  BENCH --> PASS[PASS accuracy + latency]
`````

There are **two ways** to reach a bitstream:

1. **Scripted (recommended for reproducibility):** `make board-bd` then`make board-bitstream`.
2. **GUI (what you can do once by hand):** package IP, assemble the BD in Vivado, then use the same bitstream / SD scripts.

Both end at the same topology and the same `FNN_BASE_ADDR`.

---

## 1. Repository prerequisites

On the build PC, from the repo root:

`````bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
make train && make deploy          # weights/generated/*.mem + fnn_params.vh
make golden && make sim            # must PASS before trusting a bitstream
`````

The bitstream embeds the same `weights/generated/{weights,biases}.mem` images that `make sim` used. A failing simulation predicts a failing on-board comparison.

Confirm AXI port widths on `fpga_top` / `axi4lite_slave`: **`AWADDR` / `ARADDR`are 32 bits**, with register decode on bits `[7:0]` only.

---

## 2. One-time board / tool setup

### 2.1 Tools

`````bash
source /tools/Xilinx/Vivado/2024.2/settings64.sh   # also provides bootgen
`````

### 2.2 Board config

`````bash
cp board/config.env.example board/config.env
`````

Important variables:

| Variable                         | Role                                                     |
| -------------------------------- | -------------------------------------------------------- |
| `VIVADO_PROJ` / `VIVADO_XPR` | Vivado project directory / `.xpr`                      |
| `IP_REPO`                      | Packaged `fpga_top` IP (default `board/out/ip_repo`) |
| `BITSTREAM`                    | Output `.bit` path                                     |
| `FNN_BASE_ADDR`                | Must match Address Editor (**`0x400000000`**)    |
| `PL_CLK_MHZ`                   | Used by `fnn_bench.py` to convert cycles → µs (100)  |
| `FW_DIR`                       | Prebuilt FSBL / PMUFW / ATF / U-Boot for `BOOT.BIN`    |
| `WIC_IMG`                      | Decompressed PetaLinux ZCU104 `.wic`                   |
| `SD_DEV`                       | SD block device on the build PC (e.g. `/dev/mmcblk0`)  |
| `BOARD_HOST`                   | Board IP after Ethernet comes up                         |

### 2.3 Prebuilt firmware (for `BOOT.BIN`)

`````bash
git clone --depth 1 -b xilinx_v2024.2 \
  https://github.com/Xilinx/soc-prebuilt-firmware.git \
  /path/to/zcu104_linux/soc-prebuilt-firmware
# set FW_DIR=.../soc-prebuilt-firmware/zcu104-zynqmp
`````

### 2.4 PetaLinux SD image

1. Download the **2024.2** ZCU104 SD image (`.wic.xz`) from AMD's PetaLinux release area (Yocto Native BSP / ZCU104).
2. Decompress to a `.wic` and set `WIC_IMG` in `config.env`.

This flow boots **Linux from µSD** and does **not** require JTAG for the accuracy bench.

---

## 3. Package `fpga_top` as AXI4-Lite IP

The Block Design instantiates a packaged IP (`user.org:user:fpga_top:1.0`), not loose RTL files.

### 3.1 Scripted

`````bash
make board-package
`````

What the script does:

1. Copies `rtl/accel/*`, `rtl/peripheral/*`, `rtl/include/fnn_params.vh`, and`weights/generated/*.mem` into the IP `src/` tree.
2. Points `fnn_top` `W_MEM_FILE` / `BIAS_MEM_FILE` at the packaged `.mem` paths.
3. Declares slave bus `interface_aximm` (AXI4-Lite), clock `clk`, active-low
   `rst_n`, and a **64 KiB** memory map (`reg0`) for the Address Editor.

---

## 4. Create the Vivado project and Block Design

### 4.1 Scripted

`````bash
make board-bd
`````

`board/create_bd.tcl` builds exactly this topology:

`````text
zynq_ultra_ps_e_0
  M_AXI_HPM0_FPD ──┐
  M_AXI_HPM1_FPD ──┼──► axi_smc (SmartConnect) ──► fpga_top_0 / interface_aximm
  pl_clk0 (100 MHz) ──► fpga_top.clk, smc, maxihpm*_aclk, proc_sys_reset
  pl_resetn0 ──► rst_ps8_0_100M ──► peripheral_aresetn → fpga_top.rst_n, smc.aresetn

Address Editor (PS Data):
  SEG_fpga_top_0_reg0  offset = 0x400000000   range = 64K
`````

**Why both HPM0 and HPM1?**
`0xA0000000` sits on the HPM0 aperture. The working Linux map uses **`0x400000000`**, which is a **40-bit HPM1** aperture. Enabling only HPM0 and probing `0xA0000000` from Linux caused hangs; HPM0+HPM1 with base `0x400000000` is the combination that passed.

Top of the project after the script: **`fnn_bd_wrapper`**.

### 4.2 Timing / resources

The default net (`10 → 6 → 1`, four MAC lanes) is light on the ZU7EV. If a deeper net fails timing: lower `pl_clk0`, or reduce `FNN_NUM_PE` and re-run
`make deploy`. See [synthesis.md](synthesis.md).

---

## 5. Generate the bitstream

### 5.1 Scripted

After **any** RTL change to the packaged IP (especially `axi4lite_slave`), always rebuild this way. Vivado otherwise reuses an Out-of-Context DCP and your edit never reaches the bitstream.

`````bash
make board-bitstream
`````

## 6. Build `BOOT.BIN` and flash the SD card

Linux must load **your** PL bitstream at boot. The scripts take a stock PetaLinux WIC and replace / overlay boot firmware with one that includes the FNN `.bit`.

### 6.1 Assemble `BOOT.BIN`

`````bash
make board-boot
`````

Requires `FW_DIR` (Section 2.3) and a successful `$BITSTREAM`.

### 6.2 Flash µSD on the build PC

1. Insert the SD card, note the block device (`lsblk`) → set `SD_DEV`.
2. Unmount any automounted partitions.
3. Run (writes the WIC, then overlays `BOOT.BIN` and enables root SSH):

`````bash
./board/flash_sd.sh          # needs sudo
`````

What it does, in order:

1. `dd` / write `WIC_IMG` onto `SD_DEV`.
2. Mount the boot partition, install `board/out/BOOT.BIN`.
3. Patch rootfs via `enable_ssh.sh`: root login over SSH, password `fnn`,
   optional static IP on `end0` (override with `FNN_ETH_IP`).

### 6.3 Board switches and first boot

1. Insert the SD into the ZCU104.
2. Boot mode **SW6 = ON OFF OFF OFF** (SD boot; confirm against your board's silkscreen / UG if unsure).
3. Connect **Ethernet** (RJ45 to your LAN) and **UART** (optional debug).
4. Power on.

Default after `flash_sd.sh`:

| Item              | Value                            |
| ----------------- | -------------------------------- |
| User / password   | `root` / `fnn`               |
| Static IP attempt | `192.168.178.10` on `end0`   |
| DHCP hostname     | often `zynqmp-zcu104-sdt-full` |

If DHCP wins, find the board on the LAN and set `BOARD_HOST` in `config.env` (this bring-up used e.g. `192.168.178.183`).

`````bash
ssh root@$BOARD_HOST     # password: fnn
`````

---

## 7. On-board accuracy and latency bench

From the **build PC** (repo root, `config.env` loaded by the script):

`````bash
make board-run
`````

`fnn_bench.py` (runs **on the board**):

1. `mmap` `/dev/mem` at `FNN_BASE_ADDR`.
2. For each golden vector: write 10× INT8 features via `ADDR`/`DATA`, pulse`CTRL`, poll `STATUS`, read `PRED` and `CYCLES`.
3. Compare `PRED` to `expected.bin` (software INT8 golden, **not** UNSW labels).
4. Print accuracy, mean/min/max latency (cycles and µs at `PL_CLK_MHZ`), and shost-loop throughput.

Expected success line:

`````text
PASS (82332/82332)
`````

with average cycles near **484** → **~4.84 µs** at 100 MHz.

Optional: reload PL without reflashing the SD:

`````bash
RELOAD_BIT=1 board/run_on_board.sh
`````

MMIO register map: [host.md](host.md).

---

## 8. Future work

1. Live traffic: PS (or PL) must still emit the same ten RFE-selected Q1.7 features before invoking this IP.
2. Optional Linux driver (UIO / character device) instead of `/dev/mem`.
