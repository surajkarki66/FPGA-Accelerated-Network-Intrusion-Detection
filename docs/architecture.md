# System Architecture

This describes the end-to-end architecture of an FPGA-accelerated multi-layer perceptron (MLP) for network intrusion detection. Floating-point training and evaluation are performed in software on the [UNSW-NB15](https://research.unsw.edu.au/projects/unsw-nb15-dataset) dataset. The trained model is quantized to signed **INT8 Q1.7** fixed-point arithmetic and exported into synthesisable memory initialisation files. The exported model is then executed by an FPGA accelerator implemented in synthesisable Verilog.

The hardware path is limited to **inference**.

Related documents (see also [`README.md`](README.md) in this folder):

## 1. System overview

````mermaid
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
````

`Note`: Time multiplexed means a small set of MAC units is reused in turns (tile by tile, layer by layer) instead of building one dedicated unit per neuron, trading extra cycles for less hardware.

## 2. Learning problem and model topology

### 2.1 Default network

The default binary classifier has the following structure:

<img width="1024" height="572" alt="image" src="https://github.com/user-attachments/assets/c0eb4e03-8f70-41f6-a375-340088e1ea2c" />

### 2.2 Configurable layer

Layer widths are selected at training time via `--layers` and must be re-exported with `make deploy` after any change.

| `--layers`      | Interpretation                                |
| ----------------- | --------------------------------------------- |
| `10,6,1`        | Default binary classifier                     |
| `10,64,32,16,1` | Deeper binary classifier                      |
| `10,64,32,5`    | Multi-class classifier (hardware uses argmax) |

Deployment regenerates `rtl/include/fnn_params.vh` and `weights/generated/{weights,biases}.mem`. Memory depths `FNN_W_DEPTH` and
`FNN_B_DEPTH` are sized **exactly** for the active topology, no spare headroom is reserved.

The `layer_controller` finite-state machine supports up to **eight** fully connected layers without RTL edits (`FNN_MAX_LAYERS`).
Topologies beyond that bound require an extension of the controller's per-layer parameter tables.

## 3. Data preparation

Preprocessing is implemented in `sw/model/data_unsw.py` and proceeds as follows:

1. **Categorical encoding:**  Non-numeric fields are label-encoded. Columns `id`, `label`, and `attack_cat` are removed from the feature matrix. Dropping `attack_cat` prevents label leakage into the binary task.
2. **Feature selection:** Recursive feature elimination (RFE) reduces the input to `input_dim` features (default 10). The selected feature list is cached under `artifacts/` for reproducibility.
3. **Standardisation:** A `StandardScaler` is fitted on the **training** partition only and applied to train and test splits.
4. **Fixed-point range mapping:** Features are clipped and scaled into $[-1, 1]$ so that they admit a faithful Q1.7 representation.

CSV locations and download instructions are given in [`dataset.md`](dataset.md).

## 4. Software pipeline

````mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#1e293b', 'primaryTextColor': '#f8fafc', 'primaryBorderColor': '#38bdf8', 'lineColor': '#64748b', 'secondaryColor': '#0f172a', 'tertiaryColor': '#1e293b'}}}%%
flowchart LR
    subgraph Software["Software Model & Evaluation"]
        direction LR
        train["<b>Model Training</b><br/><i>Weights & Biases</i>"]
        eval(["<b>Model Evaluation</b><br/><i>Accuracy</i>"])
        
        train --> eval
    end

    subgraph Verification["Hardware Verification & Co-Simulation"]
        direction LR
        deploy["<b>Deployment & Export</b><br/><i>Quantization & Parameter Generation</i>"]
        golden[["<b>Golden Reference</b><br/><i>Bit-Accurate Expected Outputs</i>"]]
        sim{{"<b>RTL Simulation</b><br/><i>Hardware vs. Golden Verification</i>"}}
        
        deploy --> golden --> sim
    end

    train --> deploy

    %% Styling
    classDef process fill:#0f172a,stroke:#38bdf8,stroke-width:2px,color:#f8fafc;
    classDef eval fill:#1e3a8a,stroke:#60a5fa,stroke-width:2px,color:#ffffff;
    classDef artifact fill:#312e81,stroke:#818cf8,stroke-width:2px,color:#ffffff;
    classDef sim fill:#064e3b,stroke:#34d399,stroke-width:2px,color:#ffffff;

    class train,deploy process;
    class eval eval;
    class golden artifact;
    class sim sim;

    style Software fill:#f8fafc,stroke:#cbd5e1,stroke-width:2px,color:#0f172a
    style Verification fill:#f8fafc,stroke:#cbd5e1,stroke-width:2px,color:#0f172a
````

| Stage                     | Command         | Primary ouputs                              |
| ------------------------- | --------------- | ---------------------------------------------- |
| Floating-point training   | `make train`  | `artifacts/nids_mlp.pt`                      |
| Floating-point evaluation | `make eval`   | Test-set accuracy (console)                    |
| Quantization and export   | `make deploy` | `weights/generated/*.mem`, `fnn_params.vh` |
| Golden-vector generation  | `make golden` | `sim/golden/` (UNSW test set, INT8)          |
| RTL simulation            | `make sim`    | Icarus pass/fail vs software INT8              |

Quantisation converts each dense layer's weights and biases to signed INT8 and validates that the software INT8 forward pass remains consistent with the intended decision rule. The golden reference generator then evaluates that same INT8 model on every test sample and writes features, expected predictions, and ground-truth labels for hardware comparison.

## 5. Fixed-point arithmetic (Q1.7)

Unless otherwise noted, activations, weights, and biases are **signed 8-bit** values with seven fractional bits (Q1.7). Products therefore lie in a Q2.14
domain and are accumulated in a wider signed register (32 bits).

````mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#1e293b', 'primaryTextColor': '#f8fafc', 'primaryBorderColor': '#38bdf8', 'lineColor': '#64748b', 'secondaryColor': '#0f172a', 'tertiaryColor': '#1e293b'}}}%%
flowchart LR
    subgraph Inputs["Signed 8-bit Inputs (Q1.7)"]
        direction TB
        Act[/"<b>Activation (a)</b><br/><i>INT8 [Q1.7]</i>"/]
        Wgt[/"<b>Weight (w)</b><br/><i>INT8 [Q1.7]</i>"/]
        Bias[/"<b>Bias (b)</b><br/><i>INT8 [Q1.7]</i>"/]
    end

    subgraph MAC["MAC"]
        direction LR
        Mult(("<b>Multiplier</b><br/><i>a × w → Q2.14</i>"))
        AccReg[("<b>Accumulator Register</b><br/><i>(32-bit Signed)<br/>acc←acc+(a·w)</i>")]
        BiasShift["<b>Bias Alignment</b><br/><i>b ≪ 7 <br/>[Q1.7 → Q2.14]</i>"]
        BiasAdd(("<b>Bias Adder</b><br/><i>acc←acc+(b≪7)</i>"))
        Scale["<b>Scale</b><br/><i>acc ≫ 7<br/>[Q2.14 → Q1.7]</i>"]
        Clamp["<b>Clamp</b><br/><i>y←clamp<sub>[-128,127]</sub></i>"]

        Mult --> AccReg
        AccReg -- "Loop over<br/>input index" --> AccReg
        BiasShift --> BiasAdd
        AccReg --> BiasAdd
        BiasAdd --> Scale
        Scale --> Clamp
    end

    Act --> Mult
    Wgt --> Mult
    Bias --> BiasShift

    %% Styling
    classDef input fill:#1e3a8a,stroke:#60a5fa,stroke-width:2px,color:#ffffff;
    classDef op fill:#0f172a,stroke:#38bdf8,stroke-width:2px,color:#f8fafc;
    classDef reg fill:#312e81,stroke:#818cf8,stroke-width:2px,color:#ffffff;

    class Act,Wgt,Bias input;
    class Mult,BiasShift,BiasAdd,Scale,Clamp op;
    class AccReg reg;

    style Inputs fill:#f8fafc,stroke:#cbd5e1,stroke-width:2px,color:#0f172a
    style MAC fill:#f8fafc,stroke:#cbd5e1,stroke-width:2px,color:#0f172a
````

## 6. Hardware organization

### 6.1 Module hierarchy

| Region              | Modules                                                                                                                   | Role                                         |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| `rtl/accel/`      | `fnn_top`, `layer_controller`, `shared_mac_engine`, `mac_unit`, `act_mem`, `weight_mem`, `relu`, `argmax` | Inference datapath and scheduler             |
| `rtl/peripheral/` | `fpga_top`, `axi4lite_slave`                                                                                          | Board-facing AXI4-Lite wrapper               |
| `rtl/include/`    | `fnn_params.vh`                                                                                                         | Auto-generated geometry and register offsets |


### 6.2 Accelerator datapath

````mermaid
flowchart TB
  HOST[Host / AXI] -->|INT8 features| ACT

  subgraph ACCEL["fnn_top"]
    ACT["act_mem\n(A/B ping-pong)"]
    CTRL[layer_controller]
    ENG["shared_mac_engine\n(NUM_PE MAC lanes)"]
    W[(weights.mem)]
    B[(biases.mem)]

    CTRL -->|addr / ctrl| ACT
    CTRL -->|a, clear, valid, finalize| ENG
    W --> ENG
    B --> ENG
    ENG -->|y| CTRL
    ACT -->|activation a| ENG
  end

  CTRL -->|score ≥ 0 or argmax| PRED[pred]
````

Two activation memories (**A** and **B**) implement a ping-pong buffer: layer $n$ reads from one bank while writing layer $n$ outputs into the other. Weight and bias memories are read-only ROMs initialised from the exported `.mem` files. The `layer_controller` issues addresses, PE enables, and handshake signals and the `shared_mac_engine` broadcasts a single activation sample to `FNN_NUM_PE` MAC lanes, each with a distinct weight (and, at bias time, a distinct bias).

### 6.3 Processing-element tiling

When a layer's output width exceeds `FNN_NUM_PE`, the controller evaluates the layer in successive **tiles**. For the default geometry $10 \rightarrow 6$ with `NUM_PE = 4`:

| Pass   | PE0   | PE1   | PE2       | PE3       |
| ------ | ----- | ----- | --------- | --------- |
| Tile 1 | out 0 | out 1 | out 2     | out 3     |
| Tile 2 | out 4 | out 5 | *(off)* | *(off)* |

Within a tile, for every input index $i$:

- the activation $x[i]$ is presented to every **enabled** lane;
- lane $k$ computes $\mathrm{acc}_k \mathrel{+}= x[i] \cdot W[\mathrm{out}_k][i]$.

After the input sweep, each enabled lane adds its bias, finalises to INT8, applies ReLU when the layer is hidden, and writes results into the destination activation bank. The controller then advances to the next tile or the next layer.

### 6.4 Controller scheduling (summary)

Synchronous RAM reads require a three-phase access (`REQ` → `WAIT` → `CAP`). Consequently the controller interleaves memory latency with MAC issue. At a high level, one tile proceeds as: clear accumulators; for each input, fetch activation and per-lane weights then pulse `valid`; fetch biases; finalise; capture `y`; write back; advance. Terminal states produce `pred` and assert
`done`. Detailed state names are defined in `rtl/accel/layer_controller.v`.

## 8. Host interface (summary)

The on-chip control and status interface is an **AXI4-Lite** slave with 32-bit address and data ports. Register decode uses address bits `[7:0]`;
upper bits select the memory-mapped window assigned in the SoC address map. The host loads features via `ADDR`/`DATA`, pulses `CTRL`, polls `STATUS`, and reads `PRED` (and optionally `CYCLES`). The complete map and programming sequence appear in [`host.md`](host.md).

## 9. Board integration

Recommended bring-up order:

1. `make train && make deploy` (see [`software.md`](software.md))
2. `make golden && make sim` (see [`simulation.md`](simulation.md))
3. ZCU104 bitstream → SD → `make board-run` ([`zcu104_bringup.md`](zcu104_bringup.md))
4. MMIO programming sequence ([`host.md`](host.md))

General synthesis remarks: [`synthesis.md`](synthesis.md).
