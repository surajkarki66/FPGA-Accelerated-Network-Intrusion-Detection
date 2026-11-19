#!/usr/bin/env python3
"""On-board FNN accuracy + latency benchmarking using /dev/mem."""
from __future__ import annotations

import argparse
import mmap
import os
import struct
import sys
import time

PAGE = mmap.PAGESIZE
REG_CTRL, REG_STATUS, REG_ADDR, REG_DATA, REG_PRED, REG_CYCLES = (
    0x00,
    0x04,
    0x0C,
    0x10,
    0x14,
    0x18,
)
STATUS_DONE = 1 << 0
INPUT_DIM = 10


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--features", required=True, help="features.bin")
    ap.add_argument("--expected", required=True, help="expected.bin")
    ap.add_argument(
        "--base",
        default=os.environ.get("FNN_BASE_ADDR", "0x400000000"),
        help="AXI slave base (Address Editor)",
    )
    ap.add_argument("--clk-mhz", type=float, default=float(os.environ.get("PL_CLK_MHZ", "100")))
    ap.add_argument("--start", type=int, default=0)
    ap.add_argument("--count", type=int, default=0, help="0 = all from --start")
    ap.add_argument("--report-every", type=int, default=10000)
    ap.add_argument(
        "--warmup",
        type=int,
        default=16,
        help="inferences before timing window (not scored if beyond range)",
    )
    args = ap.parse_args()
    base_addr = int(args.base, 0)

    if os.geteuid() != 0:
        print("run as root (needs /dev/mem)", file=sys.stderr)
        return 2

    feat = open(args.features, "rb").read()
    exp = open(args.expected, "rb").read()
    n = len(exp)
    if len(feat) != n * INPUT_DIM:
        print(f"size mismatch feat={len(feat)} exp={n}", file=sys.stderr)
        return 2

    end = n if args.count <= 0 else min(n, args.start + args.count)
    start = max(0, args.start)
    total = end - start
    if total <= 0:
        print("empty range", file=sys.stderr)
        return 2

    page_off = base_addr & ~(PAGE - 1)
    offset = base_addr - page_off
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    mm = mmap.mmap(
        fd, PAGE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=page_off
    )
    os.close(fd)

    def wr(reg: int, val: int) -> None:
        mm.seek(offset + reg)
        mm.write(struct.pack("<I", val & 0xFFFFFFFF))

    def rd(reg: int) -> int:
        mm.seek(offset + reg)
        return struct.unpack("<I", mm.read(4))[0]

    def infer(sample: int) -> tuple[int, int]:
        base = sample * INPUT_DIM
        for i in range(INPUT_DIM):
            wr(REG_ADDR, i)
            wr(REG_DATA, feat[base + i])
        wr(REG_CTRL, 1)
        for _ in range(1_000_000):
            if rd(REG_STATUS) & STATUS_DONE:
                break
        else:
            raise TimeoutError(f"sample {sample}")
        return rd(REG_PRED) & 0xFF, rd(REG_CYCLES)

    print(
        f"FNN bench  base=0x{base_addr:x}  clk={args.clk_mhz:g} MHz  "
        f"samples [{start},{end}) of {n}"
    )

    fails = 0
    cycle_sum = 0
    cycle_min = None
    cycle_max = 0
    first_fail = None

    # Warmup (not counted in wall timing)
    for s in range(start, min(end, start + max(0, args.warmup))):
        try:
            infer(s)
        except TimeoutError as e:
            print(f"WARMUP TIMEOUT {e}")
            mm.close()
            return 1

    t0 = time.perf_counter()
    try:
        for s in range(start, end):
            try:
                pred, cycles = infer(s)
            except TimeoutError as e:
                print(f"TIMEOUT {e}")
                fails += 1
                continue
            cycle_sum += cycles
            cycle_max = max(cycle_max, cycles)
            cycle_min = cycles if cycle_min is None else min(cycle_min, cycles)
            if pred != exp[s]:
                fails += 1
                if first_fail is None:
                    first_fail = (s, pred, exp[s], cycles)
                if fails <= 20 or fails % 100 == 0:
                    print(
                        f"sample {s}: FAIL pred={pred} expected={exp[s]} cycles={cycles}"
                    )
            if args.report_every and (s + 1 - start) % args.report_every == 0:
                done = s + 1 - start
                dt = time.perf_counter() - t0
                print(f"... {done}/{total}  fails={fails}  {done / dt:.1f} samp/s")
    finally:
        mm.close()

    wall = time.perf_counter() - t0
    ok = total - fails
    acc = 100.0 * ok / total if total else 0.0
    avg_cycles = cycle_sum / total if total else 0.0
    avg_us = avg_cycles / args.clk_mhz  # cycles / (MHz) = µs
    thr = total / wall if wall > 0 else 0.0

    print()
    print("=== Accuracy ===")
    print(f"  correct     : {ok}/{total}")
    print(f"  mismatches  : {fails}")
    print(f"  accuracy    : {acc:.4f} %")
    if first_fail:
        s, p, e, c = first_fail
        print(f"  first fail  : sample {s} pred={p} expected={e} cycles={c}")

    print("=== Latency (HW cycle counter @ PL clock) ===")
    print(f"  cycles avg  : {avg_cycles:.1f}")
    print(f"  cycles min  : {cycle_min}")
    print(f"  cycles max  : {cycle_max}")
    print(f"  latency avg : {avg_us:.3f} µs  ({args.clk_mhz:g} MHz)")

    print("=== Throughput (host MMIO loop, wall clock) ===")
    print(f"  wall time   : {wall:.3f} s")
    print(f"  throughput  : {thr:.1f} samples/s")
    print(f"  (dominated by AXI register traffic, not PL compute)")

    if fails:
        print(f"FAIL ({fails}/{total})")
        return 1
    print(f"PASS ({total}/{total})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
