#!/usr/bin/env python3
"""Quantize a float checkpoint, evaluate INT8 accuracy, and export FPGA artifacts."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import torch

from model.checkpoint import load_checkpoint
from model.config import ARTIFACTS_DIR, GENERATED_DIR
from model.data_unsw import load_unsw, to_q17
from model.export_weights import export_quant_tensors, write_params_vh
from model.quantize import quantize_model, sw_int_forward


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--ckpt",
        type=str,
        default=str(ARTIFACTS_DIR / "nids_mlp.pt"),
        help="Checkpoint path (default: artifacts/nids_mlp.pt)",
    )
    ap.add_argument(
        "--out",
        type=str,
        default=str(GENERATED_DIR),
        help="Output dir for weights.mem / biases.mem (default: weights/generated)",
    )
    ap.add_argument(
        "--n",
        type=int,
        default=0,
        help="Max test rows for INT8 check (0 = full test set)",
    )
    args = ap.parse_args()

    ckpt_path = Path(args.ckpt)
    if not ckpt_path.exists():
        raise SystemExit(f"Checkpoint not found: {ckpt_path} (run make train first)")

    model, cfg = load_checkpoint(ckpt_path)
    data = load_unsw(cfg, n_features=cfg.input_dim)

    q = quantize_model(model, cfg=cfg, rescale=True)

    with torch.no_grad():
        logits = model(torch.from_numpy(data.X_test))
        if cfg.binary:
            pred_float = (logits.squeeze(-1) >= 0).numpy().astype(np.int64)
        else:
            pred_float = logits.argmax(dim=1).numpy()
    print(f"Float accuracy after Q1.7 rescale: {(pred_float == data.y_test).mean():.4f}")

    n_check = len(data.X_test) if args.n <= 0 else min(args.n, len(data.X_test))
    correct = 0
    match_float = 0
    for i in range(n_check):
        x_q = to_q17(data.X_test[i], cfg.frac_bits)
        _, p = sw_int_forward(q, x_q)
        correct += int(p == int(data.y_test[i]))
        match_float += int(p == int(pred_float[i]))
    print(f"INT8 accuracy on {n_check} test samples: {correct / n_check:.4f}")
    print(f"INT8 match rate vs rescaled float ({n_check} samples): {match_float / n_check:.4f}")

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    export_quant_tensors(q, out, cfg)
    print(f"ROMs → {out}")

    write_params_vh(cfg)
    print(f"Wrote params VH for {cfg.layer_sizes}")


if __name__ == "__main__":
    main()
