"""Weight ROM export helpers."""

from pathlib import Path

import numpy as np

from model.config import with_layers
from model.export_weights import _to_mem_hex, export_quant_tensors, render_params_vh
from model.quantize import QuantTensors


def test_to_mem_hex_signed():
    arr = np.array([63, -94, 0, -1], dtype=np.int8)
    assert _to_mem_hex(arr) == ["3F", "A2", "00", "FF"]


def test_export_quant_tensors_sizes(tmp_path: Path):
    cfg = with_layers((4, 3, 1))
    q = QuantTensors(
        weights=[
            np.zeros((3, 4), dtype=np.int8),
            np.zeros((1, 3), dtype=np.int8),
        ],
        biases=[
            np.zeros(3, dtype=np.int8),
            np.zeros(1, dtype=np.int8),
        ],
        weight_scales=[2**-7, 2**-7],
        act_scale=2**-7,
        frac_bits=7,
    )
    w_path, b_path = export_quant_tensors(q, tmp_path, cfg)
    assert len(w_path.read_text().split()) == cfg.weight_count()
    assert len(b_path.read_text().split()) == cfg.bias_count()
    meta = (tmp_path / "export_meta.txt").read_text()
    assert "layer_sizes=[4, 3, 1]" in meta


def test_render_params_vh_exact_depths():
    cfg = with_layers((10, 6, 1))
    text = render_params_vh(cfg)
    assert "`define FNN_W_DEPTH     66" in text
    assert "`define FNN_B_DEPTH     7" in text
    assert "`define FNN_NUM_FC      2" in text
    assert "`define FNN_L0_IN      10" in text
    assert "`define FNN_L0_OUT     6" in text
