"""Q1.7 helpers and software INT8 forward (FPGA mirror)."""

import numpy as np

from model.data_unsw import hw_normalize, to_q17
from model.quantize import QuantTensors, sw_int_forward


def test_to_q17_range_and_roundtrip_scale():
    x = np.array([-1.0, -0.5, 0.0, 0.5, 1.0], dtype=np.float32)
    q = to_q17(x, frac_bits=7)
    assert q.dtype == np.int8
    assert q.min() >= -128
    assert q.max() <= 127
    # ±1.0 → ±128 would clip; ±(1 - eps) maps near ±127
    assert int(q[0]) == -128 or int(q[0]) == -127
    assert int(to_q17(np.array([127 / 128], dtype=np.float32))[0]) == 127


def test_hw_normalize_clips():
    x = np.array([[-10.0, 0.0, 10.0]], dtype=np.float32)
    y = hw_normalize(x, clip=3.0)
    assert y.min() >= -1.0
    assert y.max() <= 1.0
    np.testing.assert_allclose(y[0, 1], 0.0)


def test_sw_int_forward_matches_hand_mac():
    """Mirror tb_mac_unit: two (2*3) products + bias 1 → >>7 → 1."""
    # Single layer 1→1: w=[[3]], wait — use 2-in 1-out with two steps via vector
    # Layer: out=1, in=2, w=[[3, 3]], b=[1], a=[2, 2]
    # acc = 3*2 + 3*2 + (1<<7) = 12 + 128 = 140; >>7 = 1
    q = QuantTensors(
        weights=[np.array([[3, 3]], dtype=np.int8)],
        biases=[np.array([1], dtype=np.int8)],
        weight_scales=[2**-7],
        act_scale=2**-7,
        frac_bits=7,
    )
    scores, pred = sw_int_forward(q, np.array([2, 2], dtype=np.int8))
    assert int(scores[0]) == 1
    assert pred == 1


def test_sw_int_forward_relu_hidden():
    # Hidden layer produces negative → ReLU zeros; output sees zeros
    q = QuantTensors(
        weights=[
            np.array([[-10], [-10]], dtype=np.int8),  # 1→2
            np.array([[1, 1]], dtype=np.int8),  # 2→1
        ],
        biases=[
            np.array([0, 0], dtype=np.int8),
            np.array([0], dtype=np.int8),
        ],
        weight_scales=[2**-7, 2**-7],
        act_scale=2**-7,
        frac_bits=7,
    )
    scores, pred = sw_int_forward(q, np.array([64], dtype=np.int8))
    assert int(scores[0]) == 0
    assert pred == 1  # score >= 0
