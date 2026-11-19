# ZCU104 Implementation and Bring-Up

This guide describes the implementation and deployment of the Feedforward Neural Network (FNN) accelerator on the **AMD Zynq UltraScale+ MPSoC ZCU104** development board. It covers the FPGA implementation and board bring-up process, starting after successful RTL simulation. The workflow includes Vivado IP packaging, Block Design generation, bitstream implementation, SD-card preparation, Linux boot, and on-board hardware verification.

The accelerator communicates with the processing system (PS) through an AXI4-Lite interface. Linux accesses the accelerator through memory-mapped I/O (MMIO) using `/dev/mem`. The implementation has been validated using Vivado 2024.2 and a PetaLinux 2024.2 SD-card image.

**Validated hardware result: `PASS (82332/82332)`, with an average execution time of approximately 484 cycles (4.84 µs at 100 MHz).**

## 1. Hardware and Software Configuration

| Item | Configuration |
|---|---|
| Development board | AMD ZCU104 |
| FPGA device | `xczu7ev-ffvc1156-2-e` |
| Board part | `xilinx.com:zcu104:part0:1.1` |
| Vivado version | 2024.2 |
| PetaLinux image | 2024.2 |
| PL clock | 100 MHz (`pl_clk0`) |
| Host interface | AXI4-Lite MMIO |
| Accelerator base address | `0x400000000` |
| Address range | 64 KiB |
| On-board operating system | Linux |
| Hardware verification | `/dev/mem` and Python |

## 2. Implementation Workflow

The board implementation follows these steps:

1. Package the existing accelerator RTL and generated memory files as Vivado IP.
2. Create the Vivado project and Block Design.
3. Synthesize and implement the design.
4. Generate the FPGA bitstream.
5. Generate `BOOT.BIN` containing the FPGA bitstream.
6. Prepare the PetaLinux SD card.
7. Boot Linux on the ZCU104.
8. Run the hardware accuracy and latency benchmark.

## 3. Board and Tool Setup

### 3.1 Configure Vivado

Load the Vivado 2024.2 environment:

```bash
source /tools/Xilinx/Vivado/2024.2/settings64.sh
```

This also provides access to the required Xilinx boot utilities, including `bootgen`.

The development PC requires:

- Vivado 2024.2
- Xilinx `bootgen`
- `sshpass`
- `sudo` access for SD-card preparation
- Python dependencies required by the board scripts

### 3.2 Configure the Board Environment

Create the configuration file:

```bash
cp board/config.env.example board/config.env
```

Edit `board/config.env` and configure the following variables:

| Variable | Description |
|---|---|
| `VIVADO_PROJ` | Vivado project directory |
| `VIVADO_XPR` | Vivado project file |
| `IP_REPO` | Location of the packaged accelerator IP |
| `BITSTREAM` | Output FPGA bitstream |
| `FNN_BASE_ADDR` | Accelerator AXI base address |
| `PL_CLK_MHZ` | PL clock frequency |
| `FW_DIR` | Directory containing the prebuilt ZCU104 firmware |
| `WIC_IMG` | Decompressed PetaLinux SD-card image |
| `SD_DEV` | SD-card block device on the development PC |
| `BOARD_HOST` | IP address of the ZCU104 board |

The validated accelerator configuration uses:

```bash
FNN_BASE_ADDR=0x400000000
PL_CLK_MHZ=100
```

The base address must match the Vivado Address Editor configuration.

### 3.3 Obtain the Prebuilt Firmware

Clone the Xilinx prebuilt firmware repository:

```bash
git clone --depth 1 -b xilinx_v2024.2 \
  https://github.com/Xilinx/soc-prebuilt-firmware.git \
  /path/to/zcu104_linux/soc-prebuilt-firmware
```

Set `FW_DIR` to:

```text
/path/to/zcu104_linux/soc-prebuilt-firmware/zcu104-zynqmp
```

### 3.4 Download the PetaLinux SD Image

Download the PetaLinux 2024.2 ZCU104 SD-card image from the AMD release repository:

https://origin.petalinux.xilinx.com/sswreleases/rel-v2024.2/Yocto_Native_BSP/ZCU104/sd_image/

Download the `.wic.xz` image and extract it:

```bash
xz -dk image.wic.xz
```

Set `WIC_IMG` in `board/config.env` to the extracted `.wic` file.

This implementation boots Linux directly from the SD card and does not require JTAG for normal hardware verification.

## 4. Package the Accelerator as Vivado IP

The accelerator is integrated into the Vivado Block Design as a packaged IP rather than as individual RTL files.

Run:

```bash
make board-package
```

The packaging script performs the following operations:

1. Copies accelerator RTL files from `rtl/accel/` and `rtl/peripheral/`.
2. Includes the parameter definitions from `rtl/include/fnn_params.vh`.
3. Copies the generated weight and bias memory files.
4. Configures the memory file paths used by `fnn_top`.
5. Defines the AXI4-Lite slave interface.
6. Configures the clock and reset interfaces.
7. Creates a 64 KiB memory map for the accelerator registers.

The packaged IP is identified as:

```text
user.org:user:fpga_top:1.0
```

The main interfaces are:

| Interface | Description |
|---|---|
| `interface_aximm` | AXI4-Lite slave interface |
| `clk` | Accelerator clock |
| `rst_n` | Active-low reset |
| `reg0` | 64 KiB addressable memory map |

The packaged IP is stored in the directory specified by `IP_REPO`. The default location is:

```text
board/out/ip_repo
```

## 5. Create the Vivado Project and Block Design

The Vivado project and Block Design can be generated automatically without using the graphical interface.

Run:

```bash
make board-bd
```

This command packages the accelerator IP and creates the Vivado project and Block Design using:

```text
board/create_bd.tcl
```

### 5.1 Block Design Architecture

The Block Design contains the following components:

- **Zynq UltraScale+ Processing System:** Runs Linux and provides access to the programmable logic.
- **AXI SmartConnect:** Connects the processing system to the accelerator.
- **FNN Accelerator:** Executes neural network inference in programmable logic.
- **Processor System Reset:** Generates the required reset signals.

The main connections are:

| Signal or Interface | Connection |
|---|---|
| `M_AXI_HPM0_FPD` | AXI SmartConnect |
| `M_AXI_HPM1_FPD` | AXI SmartConnect |
| `pl_clk0` | Accelerator and AXI clock |
| `pl_resetn0` | Processor System Reset |
| `peripheral_aresetn` | Accelerator and SmartConnect reset |

### 5.2 AXI Address Configuration

The accelerator is mapped to:

```text
Base address: 0x400000000
Address range: 64 KiB
```

This address belongs to the 40-bit HPM1 address aperture.

Both HPM0 and HPM1 are enabled in the validated design. During bring-up, accessing the accelerator through the HPM0 address `0xA0000000` caused Linux to hang.

The configuration using both interfaces and the HPM1 address `0x400000000` passed hardware verification.

The generated top-level Block Design wrapper is:

```text
fnn_bd_wrapper
```

### 5.3 Additional Block Design Options

The following commands are available:

| Command | Description |
|---|---|
| `make board-package` | Package the accelerator RTL as Vivado IP. |
| `make board-bd` | Package the IP and generate the Vivado Block Design. |
| `SKIP_PACKAGE=1 make board-bd` | Recreate the Block Design using the existing packaged IP. |

The equivalent manual GUI procedure uses the same topology and address configuration.

### 5.4 Clock and Timing Considerations

The implemented neural network configuration is:

```text
Input layer:   10 neurons
Hidden layer:   6 neurons
Output layer:   1 neuron
MAC lanes:      4
```

This configuration is relatively small for the ZU7EV device.

If a larger network fails timing closure, consider:

- Reducing the PL clock frequency.
- Decreasing `FNN_NUM_PE`.
- Regenerating the hardware parameters and memory files before repackaging the IP.

Refer to `synthesis.md` for additional synthesis and timing information.

## 6. Generate the FPGA Bitstream

After generating the Block Design, run:

```bash
make board-bitstream
```

This command performs synthesis, implementation, timing analysis, and FPGA bitstream generation.

The implementation script is:

```text
board/build_bitstream.sh
```

It clears the Vivado IP cache before implementation to ensure that the latest packaged RTL is used.

**Important:** Whenever the accelerator RTL changes, rebuild the packaged IP and regenerate the bitstream. This is particularly important when modifying the AXI interface or register logic.

The recommended sequence after an RTL modification is:

```bash
make board-package
make board-bd
make board-bitstream
```

This prevents Vivado from reusing outdated IP implementation results.

## 7. Generate BOOT.BIN

The ZCU104 must load the generated FPGA bitstream during system startup.

The bitstream is included in the `BOOT.BIN` image so that the programmable logic is configured during boot.

Run:

```bash
make board-boot
```

The implementation script is:

```text
board/build_boot.sh
```

It uses `bootgen` to generate:

```text
board/out/BOOT.BIN
```

The firmware directory (`FW_DIR`) and a successfully generated FPGA bitstream must be available.

The generated `BOOT.BIN` contains the following boot components:

1. **FSBL** – First Stage Boot Loader.
2. **PMUFW** – Platform Management Unit Firmware.
3. **FNN bitstream** – FPGA configuration for the accelerator.
4. **ATF** – Arm Trusted Firmware.
5. **DTB** – Device Tree Blob describing the hardware to Linux.
6. **U-Boot** – Second-stage bootloader.

## 8. Prepare and Flash the SD Card

### 8.1 Identify the SD Card

Insert the SD card into the development PC and identify its device:

```bash
lsblk
```

Set the correct device in `board/config.env`.

For example:

```bash
SD_DEV=/dev/mmcblk0
```

Make sure that all automatically mounted SD-card partitions are unmounted.

**Warning:** Flashing overwrites the selected block device. Verify `SD_DEV` carefully before proceeding.

### 8.2 Flash the SD Card

Run:

```bash
./board/flash_sd.sh
```

The script requires `sudo` privileges.

It performs the following operations:

1. Writes the PetaLinux `.wic` image to the SD card.
2. Mounts the boot partition.
3. Copies the generated `BOOT.BIN`.
4. Configures root SSH access.
5. Optionally configures a static Ethernet IP address.

The root filesystem configuration is handled by:

```text
board/enable_ssh.sh
```

### 8.3 Configure and Boot the ZCU104

Follow these steps:

1. Insert the prepared SD card into the ZCU104.
2. Configure the boot-mode switches for SD-card boot.
3. Connect the Ethernet cable.
4. Optionally connect UART for debugging.
5. Power on the board.

The validated switch configuration is:

```text
SW6 = ON OFF OFF OFF
```

Confirm the switch orientation against the board markings and ZCU104 documentation.

### 8.4 Connect to the Board

The SD-card preparation script configures the following default credentials:

| Parameter | Default value |
|---|---|
| Username | `root` |
| Password | `fnn` |
| Static IP attempt | `192.168.178.10` |
| Network interface | `end0` |

The IP address and password can be changed using `FNN_ETH_IP` and `BOARD_PASS`, respectively.

If DHCP assigns a different address, identify the board on the local network.

The default DHCP hostname is often:

```text
zynqmp-zcu104-sdt-full
```

Update `BOARD_HOST` in `board/config.env` with the board's current IP address.

Connect using:

```bash
ssh root@$BOARD_HOST
```

For example:

```bash
ssh root@192.168.178.10
```

Once connected, Linux is running on the ZCU104 and the accelerator is available in programmable logic.

## 9. On-Board Hardware Verification

After successfully booting Linux, run the hardware verification from the development PC:

```bash
make board-run
```

The script transfers the required benchmark files to the board and executes the verification application over SSH.

The main benchmark application is:

```text
board/fnn_bench.py
```

It communicates directly with the accelerator through `/dev/mem`.

### 9.1 Prepare the Golden Reference

The script:

```text
board/pack_golden.py
```

converts the existing simulation golden memory files:

```text
sim/golden/*.mem
```

into binary files:

```text
features.bin
expected.bin
```

These files contain the input feature vectors and their corresponding software-generated INT8 reference predictions.

### 9.2 Hardware Communication

For each test vector, `fnn_bench.py` performs the following operations:

1. Maps the accelerator's physical address into the Linux process address space using `/dev/mem`.
2. Writes ten INT8 input features through the AXI4-Lite registers.
3. Starts the accelerator by writing to the control register.
4. Polls the status register until inference is complete.
5. Reads the predicted output and execution cycle count.
6. Compares the hardware prediction against the software golden reference.

The reference predictions are stored in:

```text
expected.bin
```

These are software INT8 reference outputs, not the original UNSW-NB15 dataset labels.

### 9.3 Expected Verification Result

A successful hardware verification produces:

```text
PASS (82332/82332)
```

This means that all 82,332 hardware predictions match the corresponding software golden reference predictions.

The benchmark also reports:

- Prediction accuracy.
- Average execution cycles.
- Minimum execution cycles.
- Maximum execution cycles.
- Average execution latency in microseconds.
- Host-side throughput.

### 9.4 Latency Measurement

The accelerator operates at 100 MHz.

The execution time is calculated using:

$$
T = \frac{N_{\mathrm{cycles}}}{f_{\mathrm{clock}}}
$$

For an average execution count of approximately 484 cycles:

$$
T = \frac{484}{100 \times 10^{6}\,\mathrm{Hz}} \approx 4.84\,\mu\mathrm{s}
$$

Therefore, the average accelerator execution latency is approximately **4.84 µs**.

The reported hardware latency is based on the accelerator cycle counter. Host-side throughput also includes AXI communication and software overhead.

### 9.5 Optional: Reload the FPGA Bitstream

The FPGA bitstream can be updated without reflashing the SD card.

Run:

```bash
RELOAD_BIT=1 board/run_on_board.sh
```

This transfers the updated bitstream and reloads the programmable logic using Linux `fpga_manager`.

This is useful when testing updated FPGA implementations.

## 10. Future Improvements

The current implementation demonstrates hardware inference and bit-accurate verification on the ZCU104.

The following improvements can extend the system:

1. **Live network traffic:** Integrate the feature extraction and RFE preprocessing pipeline so that the processing system can generate the ten Q1.7 input features directly from incoming network traffic.
2. **Linux driver:** Replace direct `/dev/mem` access with a dedicated Linux driver using UIO or a character device.
3. **Performance optimization:** Evaluate different numbers of MAC processing elements and clock frequencies to improve throughput.
4. **System integration:** Connect the accelerator to a complete network intrusion detection pipeline for real-time inference.