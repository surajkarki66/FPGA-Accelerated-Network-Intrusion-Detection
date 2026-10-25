"""Load trained float checkpoints for eval / deploy."""

from __future__ import annotations

from pathlib import Path

import torch

from .config import default_config, with_layers
from .model import NIDMLP


def load_checkpoint(path: Path):
    """Return ``(model, cfg)`` from ``artifacts/nids_mlp.pt``."""
    ckpt = torch.load(path, map_location="cpu", weights_only=False)
    c = ckpt["cfg"]
    cfg = with_layers(
        tuple(c["layer_sizes"]),
        num_pe=c.get("num_pe", default_config().num_pe),
    )
    model = NIDMLP(cfg)
    model.load_state_dict(ckpt["state_dict"])
    model.eval()
    return model, cfg
