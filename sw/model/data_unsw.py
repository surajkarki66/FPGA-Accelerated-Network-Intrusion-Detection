"""UNSW-NB15 dataset loading and preprocessing for the NIDS MLP."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.feature_selection import RFE
from sklearn.preprocessing import LabelEncoder, StandardScaler

from .config import ARTIFACTS_DIR, TEST_CSV, TRAIN_CSV, ModelConfig, default_config


@dataclass
class UnswBundle:
    """
    Preprocessed UNSW-NB15 split ready for training and FPGA feature prep.

    Holds scaled feature matrices, binary labels, the RFE-selected column names,
    and StandardScaler mean/scale so the same normalization can be applied later
    when converting live traffic into Q1.7 inputs.
    """

    X_train: np.ndarray
    y_train: np.ndarray
    X_test: np.ndarray
    y_test: np.ndarray
    feature_names: list[str]
    scaler_mean: np.ndarray
    scaler_scale: np.ndarray


def _label_encode_objects(df: pd.DataFrame) -> pd.DataFrame:
    """Encode categorical (object) columns with independent LabelEncoders."""
    out = df.copy()
    for col in out.columns:
        if out[col].dtype == object:
            out[col] = LabelEncoder().fit_transform(out[col].astype(str))
    return out


def _select_features(
    X: pd.DataFrame,
    y: np.ndarray,
    n_features: int,
    cache_path: Path,
    cfg: ModelConfig,
    force: bool = False,
) -> list[str]:
    """
    Select ``n_features`` columns via RFE with a RandomForest estimator.

    Results are written to `cache_path` for reuse; pass
    `force=True` (or `--force-rfe`) to recompute.
    """
    if cache_path.exists() and not force:
        data = json.loads(cache_path.read_text(encoding="utf-8"))
        feats = data["features"]
        missing = [f for f in feats if f not in X.columns]
        if not missing:
            return feats

    rfc = RandomForestClassifier(
        n_estimators=cfg.rfe_n_estimators,
        max_depth=cfg.rfe_max_depth,
        n_jobs=-1,
        random_state=42,
    )
    rfe = RFE(
        rfc,
        n_features_to_select=n_features,
        step=cfg.rfe_step,
    )
    rfe.fit(X, y)
    feats = list(X.columns[rfe.support_])

    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(
        json.dumps(
            {
                "features": feats,
                "n_features": n_features,
                "n_samples": int(len(X)),
                "rfe_on": "full_train",
                "rfe_n_estimators": cfg.rfe_n_estimators,
                "rfe_max_depth": cfg.rfe_max_depth,
                "rfe_step": cfg.rfe_step,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return feats


def load_unsw(
    cfg: ModelConfig | None = None,
    *,
    train_csv: Path = TRAIN_CSV,
    test_csv: Path = TEST_CSV,
    n_features: int | None = None,
    force_rfe: bool = False,
    drop_attack_cat: bool = True,
) -> UnswBundle:
    """
    Build scaled train/test tensors for binary intrusion detection.

    Pipeline:
      1. Label-encode categorical columns
      2. Drop id / label (and attack_cat by default — it leaks the binary label)
      3. RFE feature selection to ``n_features`` (default: cfg.input_dim)
      4. StandardScaler fit on train only; transform test with the same stats
      5. Map into [-1, 1] for Q1.7 FPGA-compatible inputs
    """
    cfg = cfg or default_config()
    n_features = n_features or cfg.input_dim

    train = _label_encode_objects(pd.read_csv(train_csv))
    test = _label_encode_objects(pd.read_csv(test_csv))

    drop_cols = ["id", "label"]
    if drop_attack_cat and "attack_cat" in train.columns:
        drop_cols.append("attack_cat")

    y_train = train["label"].to_numpy().astype(np.int64)
    y_test = test["label"].to_numpy().astype(np.int64)
    X_train_df = train.drop(columns=drop_cols)
    X_test_df = test.drop(columns=drop_cols)

    cache = ARTIFACTS_DIR / "selected_features.json"
    feats = _select_features(X_train_df, y_train, n_features, cache, cfg, force=force_rfe)
    X_train_df = X_train_df[feats]
    X_test_df = X_test_df[feats]

    scaler = StandardScaler()
    X_train = scaler.fit_transform(X_train_df).astype(np.float32)
    X_test = scaler.transform(X_test_df).astype(np.float32)
    # Normalizing input for better quantization (INT8 Q1.7) later
    X_train = hw_normalize(X_train)
    X_test = hw_normalize(X_test)

    return UnswBundle(
        X_train=X_train,
        y_train=y_train,
        X_test=X_test,
        y_test=y_test,
        feature_names=feats,
        scaler_mean=scaler.mean_.astype(np.float32),
        scaler_scale=scaler.scale_.astype(np.float32),
    )


def hw_normalize(x: np.ndarray, clip: float = 3.0) -> np.ndarray:
    """Clip standardized features and scale into [-1, 1] for INT8 Q1.7 (8-bit signed fixed-point format).
    Q1.7: Typically means 1 integer bit and 7 fractional bits.
    step_size = 2^-7"""
    return (np.clip(x, -clip, clip) / clip).astype(np.float32)


def to_q17(x: np.ndarray, frac_bits: int = 7) -> np.ndarray:
    """Quantize values already in ~[-1, 1] to signed Q1.7 INT8.
    It converts a float already in about [-1, 1] into a signed INT8 Q1.7 value
    for the FPGA.

    """
    scale = 2.0 ** (-frac_bits)
    q = np.round(np.clip(x, -1.0, 1.0) / scale).astype(np.int32)
    return np.clip(q, -128, 127).astype(np.int8)  # Integer value would be -128 to 127
