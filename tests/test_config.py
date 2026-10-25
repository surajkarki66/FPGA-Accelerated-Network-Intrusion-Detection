"""ModelConfig geometry helpers."""

from model.config import ModelConfig, with_layers


def test_default_weight_and_bias_counts():
    cfg = ModelConfig()
    assert cfg.layer_sizes == (10, 6, 1)
    assert cfg.num_fc == 2
    assert cfg.weight_count() == 10 * 6 + 6 * 1
    assert cfg.bias_count() == 6 + 1


def test_weight_bases_and_addr_width():
    cfg = with_layers((10, 6, 1))
    assert cfg.weight_bases() == [0, 60]
    assert cfg.bias_bases() == [0, 6]
    assert cfg.w_addr_w() == 7  # ceil(log2(66))
    assert cfg.act_addr_w() == 4  # ceil(log2(10))


def test_deeper_binary():
    cfg = with_layers((10, 64, 32, 16, 1))
    assert cfg.binary is True
    assert cfg.num_fc == 4
    assert cfg.weight_count() == 10 * 64 + 64 * 32 + 32 * 16 + 16 * 1
