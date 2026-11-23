# ModelSim: pnl_tracker.v against python/pnl.py vectors (sim/vectors/pnl_*.hex)
# Transcript ends with PASS/FAIL. Regenerate vectors: python ../python/gen_vectors.py
vlib work
vlog ../rtl/pnl_tracker.v ../tb/pnl_tracker_tb.v
vsim work.pnl_tracker_tb
add wave /pnl_tracker_tb/clk /pnl_tracker_tb/rst
add wave /pnl_tracker_tb/fill_valid /pnl_tracker_tb/fill_side -radix unsigned /pnl_tracker_tb/fill_px /pnl_tracker_tb/fill_qty
add wave -radix unsigned /pnl_tracker_tb/best_bid /pnl_tracker_tb/best_ask /pnl_tracker_tb/dut/mark
add wave -radix decimal /pnl_tracker_tb/position /pnl_tracker_tb/dut/cash /pnl_tracker_tb/pnl
run -all
