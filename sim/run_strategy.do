# ModelSim: strategy.v against python/strategy.py vectors (sim/vectors/strategy_*.hex)
# Transcript ends with PASS/FAIL. Regenerate vectors: python ../python/gen_vectors.py
vlib work
vlog ../rtl/strategy.v ../tb/strategy_tb.v
vsim work.strategy_tb
add wave /strategy_tb/clk /strategy_tb/resetn /strategy_tb/trigger
add wave -radix unsigned /strategy_tb/dut/state
add wave -radix unsigned /strategy_tb/best_bid /strategy_tb/bid_valid /strategy_tb/best_ask /strategy_tb/ask_valid /strategy_tb/half_spread
add wave -radix decimal /strategy_tb/position -radix unsigned /strategy_tb/skew_k
add wave -radix unsigned /strategy_tb/dut/mid2 -radix decimal /strategy_tb/dut/skew /strategy_tb/dut/bid_raw /strategy_tb/dut/ask_raw
add wave -radix unsigned /strategy_tb/quote_valid /strategy_tb/quote_ok /strategy_tb/quote_bid_px /strategy_tb/quote_ask_px /strategy_tb/quote_size
run -all
