.PHONY: golden sim lint lint-py format test train train-deeper eval deploy hooks ci-smoke \
	board-package board-bd board-bitstream board-boot board-pack board-run

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

# Float train
train:
	PYTHONPATH=sw python3 sw/train.py --layers 10,6,1 --epochs 15

train-deeper:
	PYTHONPATH=sw python3 sw/train.py --layers 10,64,32,16,1 --epochs 15

# Float test accuracy
eval:
	PYTHONPATH=sw python3 sw/eval.py

# Quantize → INT8 evaluation → weights/generated + fnn_params.vh
deploy:
	PYTHONPATH=sw python3 sw/deploy.py

# --- ZCU104 board
board-package:
	./board/package_fpga_top.sh

board-bd:
	./board/create_bd.sh

board-bitstream:
	./board/build_bitstream.sh

board-boot:
	./board/build_boot.sh

board-pack: golden
	python3 board/pack_golden.py

board-run: board-pack
	./board/run_on_board.sh
