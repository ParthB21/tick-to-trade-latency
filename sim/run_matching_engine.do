# ModelSim: matching engine on its own (named cases + 500 random vectors vs python/matching.py)
# Regenerate vectors first if needed:  python ../python/gen_match_vectors.py
vlib work
vlog ../rtl/matching_engine.v ../tb/matching_engine_tb.v
vsim work.matching_engine_tb
add wave /matching_engine_tb/clk /matching_engine_tb/resetn
add wave -divider "Our quote (from risk gate)"
add wave /matching_engine_tb/order_valid /matching_engine_tb/our_bid_live -radix unsigned /matching_engine_tb/our_bid_px
add wave /matching_engine_tb/our_ask_live -radix unsigned /matching_engine_tb/our_ask_px /matching_engine_tb/our_size
add wave -divider "Trade event (from order book)"
add wave /matching_engine_tb/trade_valid /matching_engine_tb/trade_side -radix unsigned /matching_engine_tb/trade_price /matching_engine_tb/trade_qty
add wave -divider "Compare"
add wave /matching_engine_tb/dut/bid_hit /matching_engine_tb/dut/ask_hit
add wave -divider "Fill out"
add wave /matching_engine_tb/fill_valid /matching_engine_tb/fill_side -radix unsigned /matching_engine_tb/fill_px /matching_engine_tb/fill_qty
add wave -radix unsigned /matching_engine_tb/bid_rem /matching_engine_tb/ask_rem /matching_engine_tb/fill_count
run -all
# named cases are 60..820 ns
wave zoom range 40ns 840ns
