# FPGA-Accelerated Network Intrusion Detection

This is an implementation of an FPGA-accelerated network intrusion detection using a neural network. A compact multi-layer perceptron (MLP) is trained in floating point on the [UNSW-NB15](https://research.unsw.edu.au/projects/unsw-nb15-dataset) dataset, then quantized to signed **INT8 Q1.7** fixed-point arithmetic so that the model can be executed in programmable logic (PL). The accelerator executes the network with shared multiply–accumulate processing elements and returns a class prediction. 
Host-side software communicates with the accelerator through the **AXI4-Lite** interface, with the AMD Zynq UltraScale+ **ZCU104** serving as the target platform.

The default network topology is:

<img width="1024" height="572" alt="image" src="https://github.com/user-attachments/assets/c0eb4e03-8f70-41f6-a375-340088e1ea2c" />

Deeper or multi-class models are supported by retraining and re-exporting parameters.


## Documentation

For setting up and detailed explanation about the project:

| Document                                 | Topic                                              |
| ---------------------------------------- | -------------------------------------------------- |
| [Architecture](docs/architecture.md)      | System design, quantization, datapath              |
| [Software](docs/software.md)              | Training / evaluation / deployment                 |
| [RTL](docs/rtl.md)                        | Verilog modules                                    |
| [Simulation](docs/simulation.md)          | Icarus and golden vectors                  |
| [Host interface](docs/host.md)            | AXI4-Lite register map                             |
| [Synthesis](docs/synthesis.md)            | Vendor tools and resource knobs                    |
| [ZCU104 bring-up](docs/zcu104_bringup.md) | Automation scripts                                 |


## License

See [LICENSE](LICENSE). 

## Dataset
Dataset: [UNSW-NB15](https://research.unsw.edu.au/projects/unsw-nb15-dataset)

**Reference**
1. [verilog_MNIST_accelerator](https://github.com/loonamanik/verilog_MNIST_accelerator),
2. [ZFTurbo digit detector](https://github.com/ZFTurbo/Verilog-Generator-of-Neural-Net-Digit-Detector-for-FPGA),
