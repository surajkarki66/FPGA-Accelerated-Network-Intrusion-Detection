#!/usr/bin/env python3
"""Evaluate a trained float checkpoint on the UNSW-NB15 test set."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import torch

from model.checkpoint import load_checkpoint
from model.config import ARTIFACTS_DIR
from model.data_unsw import load_unsw


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--ckpt",
        type=str,
        default=str(ARTIFACTS_DIR / "nids_mlp.pt"),
        help="Checkpoint path (default: artifacts/nids_mlp.pt)",
    )
    args = ap.parse_args()

    ckpt_path = Path(args.ckpt)
    if not ckpt_path.exists():
        raise SystemExit(f"Checkpoint not found: {ckpt_path} (run make train first)")

    model, cfg = load_checkpoint(ckpt_path)
    data = load_unsw(cfg, n_features=cfg.input_dim)

    with torch.no_grad():
        logits = model(torch.from_numpy(data.X_test))
        if cfg.binary:
            pred = (logits.squeeze(-1) >= 0).numpy().astype(np.int64)
        else:
            pred = logits.argmax(dim=1).numpy()

    print(f"Float test accuracy: {(pred == data.y_test).mean():.4f}")
    print(f"layers={list(cfg.layer_sizes)}  n_test={len(data.y_test)}")


if __name__ == "__main__":
    main()
