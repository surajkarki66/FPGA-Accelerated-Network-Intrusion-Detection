"""Post-training quantization to signed Q1.7 (INT8) for FPGA export."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import torch

from .config import ModelConfig
from .model import NIDMLP


@dataclass
class QuantTensors:
    """Per-layer INT8 weights/biases plus scale metadata for FPGA ROMs."""

    weights: list[np.ndarray]  # int8 (out, in) per FC
    biases: list[np.ndarray]  # int8 (out,)
    weight_scales: list[float]
    act_scale: float
    frac_bits: int


def _quantize_tensor(x: np.ndarray, scale: float, bits: int = 8) -> np.ndarray:
    """It maps a float tensor to signed INT8 with a uniform scale."""
    qmax = (1 << (bits - 1)) - 1  # 127 => (1 << n = 2^n); left shift operator
    qmin = -(1 << (bits - 1))  # -128
    q = np.round(x / scale).astype(np.int32)  # divide by scale => round to nearest integer
    return np.clip(q, qmin, qmax).astype(np.int8)  # clip into [-qmin, qmax]


def rescale_for_fixed_point(model: NIDMLP, max_abs: float = 1.0) -> None:
    """Shrink each layer so |W|,|b| <= max_abs before Q1.7 quant.
    This prepares float weights so they fit Q1.7 without heavy clipping.
    """
    with torch.no_grad():
        for linear in model.fc_layers():
            # Find peak = max(|W|, |b|)
            peak = max(
                float(linear.weight.data.abs().max()),
                float(linear.bias.data.abs().max()),
                1e-8,
            )
            if peak > max_abs:
                s = max_abs / peak
                # multiply both by s: the largest magnitude becomes 1.0, everything else scales down with it.
                # then _quantize_tensor can use scale without crushing big weights into ±127 incorrectly relative to the HW MAC.
                linear.weight.data.mul_(s)
                linear.bias.data.mul_(s)


def quantize_model(
    model: NIDMLP,
    calib_x: torch.Tensor | None = None,
    cfg: ModelConfig | None = None,
    *,
    rescale: bool = True,
) -> QuantTensors:
    cfg = cfg or model.cfg
    frac = cfg.frac_bits
    act_scale = 2.0 ** (-frac)
    weights_q: list[np.ndarray] = []
    biases_q: list[np.ndarray] = []
    w_scales: list[float] = []

    if rescale:
        rescale_for_fixed_point(model, max_abs=1.0 - act_scale)  # 127 × 2^-7 = 127/128 ≈ 0.9922

    # Quantize W and bias with the same Q1.7 scale the FPGA MAC uses.
    model.eval()
    with torch.no_grad():
        for linear in model.fc_layers():
            w = linear.weight.detach().cpu().numpy()
            b = linear.bias.detach().cpu().numpy()
            w_scales.append(act_scale)
            weights_q.append(_quantize_tensor(w, act_scale))
            biases_q.append(_quantize_tensor(b, act_scale))

    # TODO: use calib_x to collect activation ranges and choose per-layer
    #       scales (real PTQ calibration). Currently ignored; scale is fixed Q1.7.
    _ = calib_x

    return QuantTensors(
        weights=weights_q,
        biases=biases_q,
        weight_scales=w_scales,
        act_scale=act_scale,
        frac_bits=frac,
    )


def sw_int_forward(q: QuantTensors, x_q: np.ndarray) -> tuple[np.ndarray, int]:
    """
    Run INT8 inference that mirrors the FPGA datapath.

    For each layer: accumulate A*W, add bias<<frac, shift>>frac, saturate to
    INT8; apply ReLU on hidden layers. Returns (output scores, class id) where
    binary nets use score>=0 and multi-class nets use argmax.
    """
    frac = q.frac_bits
    a = x_q.astype(np.int32)
    for li, (w, b) in enumerate(zip(q.weights, q.biases, strict=True)):
        # sum of products + aligned bias
        acc = (w.astype(np.int32) @ a) + (b.astype(np.int32) << frac)
        y = np.right_shift(acc, frac)
        y = np.clip(y, -128, 127).astype(np.int8)  # INT32 Q2.14 → INT8 Q1.7
        if li < len(q.weights) - 1:
            y = np.maximum(y, 0).astype(np.int8)  # ReLU
        a = y.astype(np.int32)
    scores = a.astype(np.int8)
    if scores.size == 1:
        pred = int(scores[0] >= 0)
    else:
        pred = int(np.argmax(scores))
    return scores, pred
