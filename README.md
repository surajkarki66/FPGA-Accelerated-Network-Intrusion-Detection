# FPGA-Accelerated Network Intrusion Detection

This is an implementation of an FPGA-accelerated network intrusion detection using a neural network. A compact multi-layer perceptron (MLP) is trained in floating point on the [UNSW-NB15](https://research.unsw.edu.au/projects/unsw-nb15-dataset) dataset, then quantized to signed **INT8 Q1.7** fixed-point arithmetic so that the model can be executed in programmable logic (PL). The accelerator executes the network with shared multiply–accumulate processing elements and returns a class prediction. 
Host-side software communicates with the accelerator through the **AXI4-Lite** interface, with the AMD Zynq UltraScale+ **ZCU104** serving as the target platform.

The default network topology is:

<img width="1024" height="572" alt="image" src="https://github.com/user-attachments/assets/c0eb4e03-8f70-41f6-a375-340088e1ea2c" />

Deeper or multi-class models are supported by retraining and re-exporting parameters.

The end-to-end flow is given below:

`````mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#1e293b', 'primaryTextColor': '#f8fafc', 'primaryBorderColor': '#38bdf8', 'lineColor': '#64748b', 'secondaryColor': '#0f172a', 'tertiaryColor': '#1e293b'}}}%%
flowchart LR
    subgraph Offline["Offline Training & Quantization"]
        direction LR
        CSV[("<b>UNSW-NB15 Dataset</b><br/><i>(CSV)</i>")]
        Train["<b>Model Training</b><br/><i>Feed-Forward Neural Network</i>"]
        Deploy["<b>Deployment</b><br/><i>Quantization & Export</i>"]
        
        CSV --> Train --> Deploy
    end

    ROM[["<b>Configuration & Parameters</b><br/>(<code>.mem</code> Weights + <code>params.vh</code>)"]]

    subgraph Host["Host (CPU)"]
        direction LR
        User(["<b>User Input</b><br/><i>Raw Network Traffic Data</i>"])
        Feat[/"<b>Pre-processing</b><br/><i>INT8 Feature Vectors</i>"/]
        
        User --> Feat
    end

    subgraph Hardware["FPGA"]
        direction LR
        FPGA{{"<b>FPGA Inference Engine</b><br/>"}}
    end

    Pred(["<b>Output</b><br/><i>Attack / Not Attack</i>"])

    Deploy --> ROM
    ROM --> FPGA
    Feat --> FPGA
    FPGA --> Pred

    %% Styling
    classDef dataset fill:#1e3a8a,stroke:#60a5fa,stroke-width:2px,color:#ffffff;
    classDef user fill:#475569,stroke:#94a3b8,stroke-width:2px,color:#ffffff;
    classDef process fill:#0f172a,stroke:#38bdf8,stroke-width:2px,color:#f8fafc;
    classDef artifact fill:#312e81,stroke:#818cf8,stroke-width:2px,color:#ffffff;
    classDef fpga fill:#064e3b,stroke:#34d399,stroke-width:2px,color:#ffffff;
    classDef output fill:#7f1d1d,stroke:#f87171,stroke-width:2px,color:#ffffff;

    class CSV dataset;
    class User user;
    class Train,Deploy,Feat process;
    class ROM artifact;
    class FPGA fpga;
    class Pred output;

    style Offline fill:#f8fafc,stroke:#cbd5e1,stroke-width:2px,color:#0f172a
    style Host fill:#f8fafc,stroke:#cbd5e1,stroke-width:2px,color:#0f172a
    style Hardware fill:#f8fafc,stroke:#cbd5e1,stroke-width:2px,color:#0f172a
`````

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
