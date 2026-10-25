"""MLP topology and repository paths shared by training and FPGA export."""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ModelConfig:
    """
    Topology is fully described by ``layer_sizes``:

        (input_dim, hidden_1, ..., hidden_k, output_dim)

    Default NID MLP: 10 Input features → 6 Hidden features → ReLU → Output (1 logit).
    """

    layer_sizes: tuple[int, ...] = (10, 6, 1)
    data_width: int = 8
    frac_bits: int = 7  # signed Q1.7 fixed-point
    num_pe: int = 4  # parallel MAC lanes in the RTL engine
    binary: bool = True  # True → single logit + threshold; False → argmax
    max_layers: int = 8  # must match RTL FNN_MAX_LAYERS

    # RFE (RandomForest) feature-selection hyperparameters
    rfe_n_estimators: int = 32
    rfe_max_depth: int = 12
    rfe_step: float = 0.2  # fraction of features dropped each RFE iteration

    def __post_init__(self) -> None:
        if len(self.layer_sizes) < 2:
            raise ValueError("layer_sizes needs at least input and output")
        if len(self.layer_sizes) - 1 > self.max_layers:
            raise ValueError(
                f"Need {len(self.layer_sizes) - 1} FC layers but max_layers={self.max_layers}"
            )
        if self.binary and self.layer_sizes[-1] != 1:
            raise ValueError("binary=True requires output dim 1")
        if not self.binary and self.layer_sizes[-1] < 2:
            raise ValueError("multi-class needs output dim >= 2")

    @property
    def input_dim(self) -> int:
        return self.layer_sizes[0]

    @property
    def output_dim(self) -> int:
        return self.layer_sizes[-1]

    @property
    def num_fc(self) -> int:
        return len(self.layer_sizes) - 1

    @property
    def hidden_sizes(self) -> tuple[int, ...]:
        return self.layer_sizes[1:-1]

    def weight_count(self) -> int:
        s = self.layer_sizes
        return sum(s[i] * s[i + 1] for i in range(len(s) - 1))

    def bias_count(self) -> int:
        return sum(self.layer_sizes[1:])

    def max_width(self) -> int:
        return max(self.layer_sizes)

    def act_addr_w(self) -> int:
        return max(1, math.ceil(math.log2(self.max_width())))

    def w_addr_w(self) -> int:
        return max(1, math.ceil(math.log2(max(self.weight_count(), self.bias_count(), 2))))

    def weight_bases(self) -> list[int]:
        bases = [0]
        s = self.layer_sizes
        for i in range(len(s) - 2):
            bases.append(bases[-1] + s[i] * s[i + 1])
        return bases

    def bias_bases(self) -> list[int]:
        bases = [0]
        s = self.layer_sizes
        for i in range(1, len(s) - 1):
            bases.append(bases[-1] + s[i])
        return bases


REPO_ROOT = Path(__file__).resolve().parents[2]
WEIGHTS_DIR = REPO_ROOT / "weights"
GENERATED_DIR = WEIGHTS_DIR / "generated"
ARTIFACTS_DIR = REPO_ROOT / "artifacts"
PARAMS_VH = REPO_ROOT / "rtl" / "include" / "fnn_params.vh"

# UNSW-NB15 CSVs (repo root)
TRAIN_CSV = REPO_ROOT / "dataset" / "UNSW_NB15_training-set.csv"
TEST_CSV = REPO_ROOT / "dataset" / "UNSW_NB15_testing-set.csv"

# Default binary classifier used for bring-up and FPGA export
DEFAULT_MLP = ModelConfig(layer_sizes=(10, 6, 1), binary=True, num_pe=4)


def default_config() -> ModelConfig:
    return DEFAULT_MLP


def with_layers(sizes: Sequence[int], *, binary: bool | None = None, **kwargs) -> ModelConfig:
    """Build a ModelConfig from an explicit layer-size sequence."""
    sizes_t = tuple(int(x) for x in sizes)
    if binary is None:
        binary = sizes_t[-1] == 1
    return ModelConfig(layer_sizes=sizes_t, binary=binary, **kwargs)
