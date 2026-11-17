# ModelSim: risk_gate.v against python/risk.py vectors (sim/vectors/risk_*.hex)
vlib work
vlog ../rtl/risk_gate.v ../tb/risk_gate_tb.v
vsim work.risk_gate_tb
add wave /risk_gate_tb/clk /risk_gate_tb/rst /risk_gate_tb/kill_sw /risk_gate_tb/quote_valid /risk_gate_tb/quote_ok
add wave -radix unsigned /risk_gate_tb/quote_bid_px /risk_gate_tb/quote_ask_px /risk_gate_tb/quote_size
add wave -radix unsigned /risk_gate_tb/best_bid /risk_gate_tb/best_ask
add wave -radix decimal /risk_gate_tb/position -radix unsigned /risk_gate_tb/max_pos
add wave -radix decimal /risk_gate_tb/dut/pos_buy /risk_gate_tb/dut/pos_sell
add wave /risk_gate_tb/order_valid /risk_gate_tb/our_bid_live -radix unsigned /risk_gate_tb/our_bid_px
add wave /risk_gate_tb/our_ask_live -radix unsigned /risk_gate_tb/our_ask_px
add wave /risk_gate_tb/killed -radix binary /risk_gate_tb/reject
run -all
