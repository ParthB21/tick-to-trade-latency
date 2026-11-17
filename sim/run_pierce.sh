#!/bin/sh
# Runs all of Pierce's tests with Icarus Verilog (brew install icarus-verilog).
# Same testbenches as the ModelSim .do scripts. Exits non-zero on any failure.
set -e
cd "$(dirname "$0")"
mkdir -p out
BUILD=out/build
mkdir -p "$BUILD"

run() {  # name, files...
    name=$1; shift
    iverilog -g2005 -Wno-timescale -o "$BUILD/$name.vvp" "$@"
    vvp -n "$BUILD/$name.vvp" | grep -v -E 'WARNING|\$finish' | tee "$BUILD/$name.log"
    grep -q '^PASS' "$BUILD/$name.log"
}

python3 ../python/gen_vectors.py
run strategy  ../rtl/strategy.v  ../tb/strategy_tb.v
run risk_gate ../rtl/risk_gate.v ../tb/risk_gate_tb.v
run hft_top   ../rtl/market_rom.v ../rtl/feed_handler.v ../rtl/prio_enc64.v ../rtl/order_book.v \
              ../rtl/seg7.v ../rtl/sync2.v ../rtl/strategy.v ../rtl/risk_gate.v ../rtl/dashboard.v \
              ../rtl/hft_top.v ../tb/mocks/vga_adapter.v ../tb/hft_top_tb.v
python3 ../python/e2e.py ../mem/market_data.hex out
