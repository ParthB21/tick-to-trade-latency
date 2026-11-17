# ModelSim: the exact board top level, pressing KEY[1] once per message
# The transcript prints what the HEX displays show after every press.
vlib work
vlog ../rtl/market_rom.v ../rtl/feed_handler.v ../rtl/prio_enc64.v ../rtl/order_book.v ../rtl/seg7.v ../rtl/milestone1_top.v ../tb/milestone1_top_tb.v
vsim work.milestone1_top_tb
add wave /milestone1_top_tb/CLOCK_50 /milestone1_top_tb/KEY /milestone1_top_tb/SW
add wave /milestone1_top_tb/dut/step_pulse /milestone1_top_tb/dut/go
add wave -radix unsigned /milestone1_top_tb/dut/best_bid /milestone1_top_tb/dut/best_ask /milestone1_top_tb/dut/msg_count
add wave /milestone1_top_tb/HEX5 /milestone1_top_tb/HEX4 /milestone1_top_tb/HEX3 /milestone1_top_tb/HEX2 /milestone1_top_tb/HEX1 /milestone1_top_tb/HEX0
add wave /milestone1_top_tb/LEDR
run -all
