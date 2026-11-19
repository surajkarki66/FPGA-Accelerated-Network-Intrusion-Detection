# FPGA-Accelerated Network Intrusion Detection

This repository provides an end-to-end flow for **FPGA-accelerated network intrusion detection**. A compact multi-layer perceptron (MLP) is trained in floating point on the [UNSW-NB15](https://research.unsw.edu.au/projects/unsw-nb15-dataset) corpus, then quantised to signed **INT8 Q1.7** fixed-point arithmetic so that the same numerical model can be executed in programmable logic. Recursive feature elimination reduces each flow record to a small feature vector; the accelerator evaluates the network with shared multiply–accumulate processing elements and returns a class decision. Host software programs the design over **AXI4-Lite**, targeting AMD Zynq UltraScale+ platforms such as the **ZCU104**. The default topology is **10 → 6 → 1** (binary: score ≥ 0 ⇒ attack). Deeper or multi-class schedules are supported by retraining and re-exporting parameters.

`````mermaid
flowchart LR
  CSV[UNSW-NB15] --> Train[train / eval]
  Train --> Deploy[deploy INT8]
  Deploy --> ROM[".mem + params.vh"]
  ROM --> FPGA[FPGA FNN + PEs]
  Feat[INT8 features] --> FPGA
  FPGA --> Pred[pred]
`````

## Documentation

For setup and detailed explanation:

| Document                                 | Topic                                              |
| ---------------------------------------- | -------------------------------------------------- |
| [Architecture](docs/architecture.md)      | System design, Quantization, Datapath              |
| [Software](docs/software.md)              | Train / eval / deploy / export                     |
| [RTL](docs/rtl.md)                        | Verilog modules and reading order                  |
| [Simulation](docs/simulation.md)          | Icarus benches and golden vectors                  |
| [Host interface](docs/host.md)            | AXI4-Lite register map                             |
| [Synthesis](docs/synthesis.md)            | Vendor tools and resource knobs                    |
| [ZCU104 bring-up](docs/zcu104_bringup.md) | Automated + GUI board procedure                    |
| [Board scripts](board/README.md)          | Bitstream → SD image → on-board accuracy/latency |
| [Dataset](docs/dataset.md)                | UNSW-NB15 download and layout                      |

## Quick start

`````bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
pip install -r requirements-dev.txt
make hooks
# Place CSVs: see dataset/README.md

make train && make eval && make deploy
make golden && make sim
`````

### ZCU104 (Linux image + on-board bench)

`````bash
cp board/config.env.example board/config.env   # edit paths / SSH
make board-bd                                  # package IP + create Vivado BD
make board-bitstream                           # Vivado → .bit
make board-boot                                # BOOT.BIN
./board/flash_sd.sh                            # WIC + BOOT → µSD
# boot board, Ethernet, SSH
make board-run                                 # accuracy + latency over SSH
`````

## License and dataset

See [LICENSE](LICENSE). Dataset terms: [UNSW-NB15](https://research.unsw.edu.au/projects/unsw-nb15-dataset)

Design ideas consulted from:
[verilog_MNIST_accelerator](https://github.com/loonamanik/verilog_MNIST_accelerator),
[ZFTurbo digit detector](https://github.com/ZFTurbo/Verilog-Generator-of-Neural-Net-Digit-Detector-for-FPGA),
[cnn-fpga](https://github.com/mjao1/cnn-fpga).
