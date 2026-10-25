#!/usr/bin/env python3
"""Train the UNSW-NB15 float MLP and save a checkpoint."""

from __future__ import annotations

import argparse
import json

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

from model.config import ARTIFACTS_DIR, ModelConfig, default_config, with_layers
from model.data_unsw import load_unsw
from model.model import NIDMLP


def train(
    cfg: ModelConfig,
    X_train: np.ndarray,
    y_train: np.ndarray,
    X_val: np.ndarray,
    y_val: np.ndarray,
    epochs: int,
    batch: int,
    lr: float,
    device: str,
) -> NIDMLP:
    """Train NIDMLP with BCE-with-logits (binary) or cross-entropy (multi-class)."""
    ds = TensorDataset(
        torch.from_numpy(X_train),
        torch.from_numpy(y_train.astype(np.float32 if cfg.binary else np.int64)),
    )
    loader = DataLoader(ds, batch_size=batch, shuffle=True)

    model = NIDMLP(cfg).to(device)
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = nn.BCEWithLogitsLoss() if cfg.binary else nn.CrossEntropyLoss()

    for ep in range(epochs):
        model.train()
        total = 0.0
        for xb, yb in loader:
            xb = xb.to(device)
            yb = yb.to(device)
            opt.zero_grad()
            logits = model(xb)
            if cfg.binary:
                loss = loss_fn(logits.squeeze(-1), yb)
            else:
                loss = loss_fn(logits, yb.long())
            loss.backward()
            opt.step()
            total += float(loss.item()) * len(xb)

        model.eval()
        with torch.no_grad():
            logits = model(torch.from_numpy(X_val).to(device))
            if cfg.binary:
                pred = (logits.squeeze(-1) >= 0).cpu().numpy().astype(np.int64)
            else:
                pred = logits.argmax(dim=1).cpu().numpy()
            acc = (pred == y_val).mean()
        print(f"epoch {ep + 1:03d}  loss={total / len(X_train):.4f}  val_acc={acc:.4f}")

    return model.cpu()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--layers",
        type=str,
        default="10,6,1",
        help="Comma-separated sizes: input,hiddens...,output (default: 10,6,1)",
    )
    ap.add_argument("--epochs", type=int, default=15)
    ap.add_argument("--batch", type=int, default=256)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--force-rfe", action="store_true", help="Recompute RFE feature set")
    args = ap.parse_args()

    sizes = tuple(int(x) for x in args.layers.split(","))
    cfg = with_layers(sizes, num_pe=default_config().num_pe)
    print(f"Config: layers={cfg.layer_sizes} binary={cfg.binary} num_fc={cfg.num_fc}")

    data = load_unsw(cfg, n_features=cfg.input_dim, force_rfe=args.force_rfe)

    # Shuffled validation split (CSV rows are class-ordered)
    n = len(data.X_train)
    n_val = max(1000, n // 10)
    rng = np.random.default_rng(0)
    perm = rng.permutation(n)
    X_all, y_all = data.X_train[perm], data.y_train[perm]
    X_tr, X_va = X_all[:-n_val], X_all[-n_val:]
    y_tr, y_va = y_all[:-n_val], y_all[-n_val:]

    model = train(cfg, X_tr, y_tr, X_va, y_va, args.epochs, args.batch, args.lr, args.device)

    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    ckpt = ARTIFACTS_DIR / "nids_mlp.pt"
    torch.save(
        {
            "cfg": {
                "layer_sizes": list(cfg.layer_sizes),
                "binary": cfg.binary,
                "frac_bits": cfg.frac_bits,
                "num_pe": cfg.num_pe,
            },
            "feature_names": data.feature_names,
            "scaler_mean": data.scaler_mean,
            "scaler_scale": data.scaler_scale,
            "state_dict": model.state_dict(),
        },
        ckpt,
    )
    (ARTIFACTS_DIR / "features.json").write_text(
        json.dumps({"features": data.feature_names}, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Saved {ckpt}")
    print(f"Selected features: {data.feature_names}")


if __name__ == "__main__":
    main()
