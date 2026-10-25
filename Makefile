.PHONY: golden sim lint lint-py format test train train-deeper eval deploy hooks ci-smoke

# PYTHONPATH=sw makes `import model...` resolve to sw/model/
golden:
	PYTHONPATH=sw python3 sw/generate_test_vectors.py

sim: golden
	./scripts/sim.sh

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Irtl/include --top-module fpga_top \
	  rtl/accel/*.v rtl/peripheral/*.v

lint-py:
	ruff check sw tests scripts/ci_smoke_export.py
	ruff format --check sw tests scripts/ci_smoke_export.py

format:
	ruff check --fix sw tests scripts/ci_smoke_export.py
	ruff format sw tests scripts/ci_smoke_export.py

test:
	pytest

hooks:
	pre-commit install

ci-smoke:
	PYTHONPATH=sw python3 scripts/ci_smoke_export.py
	./scripts/sim.sh

# Float train → artifacts/nids_mlp.pt
train:
	PYTHONPATH=sw python3 sw/train.py --layers 10,6,1 --epochs 15

train-deeper:
	PYTHONPATH=sw python3 sw/train.py --layers 10,64,32,16,1 --epochs 15

# Float test accuracy
eval:
	PYTHONPATH=sw python3 sw/eval.py

# Quantize → INT8 eval → weights/generated + fnn_params.vh
deploy:
	PYTHONPATH=sw python3 sw/deploy.py
