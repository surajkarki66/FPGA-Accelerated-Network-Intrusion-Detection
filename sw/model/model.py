"""PyTorch MLP mirroring the FPGA feed-forward topology."""

from __future__ import annotations

import torch
import torch.nn as nn

from .config import ModelConfig, default_config


class NIDMLP(nn.Module):
    """
    Fully connected network defined by `ModelConfig.layer_sizes`.

    Hidden layers use ReLU. The final layer is linear (no sigmoid) so that
    binary decisions on the FPGA can use a simple score >= 0 threshold.
    """

    def __init__(self, cfg: ModelConfig | None = None):
        super().__init__()
        cfg = cfg or default_config()
        self.cfg = cfg
        sizes = cfg.layer_sizes
        layers: list[nn.Module] = []
        for i in range(len(sizes) - 2):
            layers.append(nn.Linear(sizes[i], sizes[i + 1]))
            layers.append(nn.ReLU(inplace=True))
        layers.append(nn.Linear(sizes[-2], sizes[-1]))
        self.net = nn.Sequential(*layers)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)

    def fc_layers(self) -> list[nn.Linear]:
        """Return Linear modules in forward order (for weight export)."""
        return [m for m in self.net if isinstance(m, nn.Linear)]
