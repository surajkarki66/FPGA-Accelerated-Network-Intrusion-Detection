#!/usr/bin/env python3
"""Pack sim/golden/*.mem into compact binaries for on-board benchmarking."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--repo",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=None,
        help="output directory (default: board/out/golden)",
    )
    args = ap.parse_args()
    out = args.out or (args.repo / "board" / "out" / "golden")
    out.mkdir(parents=True, exist_ok=True)

    feat_path = args.repo / "sim" / "golden" / "features.mem"
    exp_path = args.repo / "sim" / "golden" / "expected.mem"
    if not feat_path.is_file() or not exp_path.is_file():
        raise SystemExit(f"missing golden mems — run `make golden` first ({feat_path})")

    feat = np.array([int(x, 16) for x in feat_path.read_text().split()], dtype=np.uint8)
    exp = np.array([int(x, 16) for x in exp_path.read_text().split()], dtype=np.uint8)
    if len(feat) != len(exp) * 10:
        raise SystemExit(
            f"size mismatch: feat={len(feat)} exp={len(exp)} (want 10 features/sample)"
        )

    feat.tofile(out / "features.bin")
    exp.tofile(out / "expected.bin")
    meta = out / "meta.txt"
    meta.write_text(
        f"n_samples={len(exp)}\n"
        f"input_dim=10\n"
        f"feat_bytes={len(feat)}\n"
        f"class1={(exp == 1).sum()}\n"
        f"class0={(exp == 0).sum()}\n",
        encoding="utf-8",
    )
    print(f"Wrote {out}/features.bin  expected.bin  ({len(exp)} samples)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
