# ModelSim: full system (ROM -> feed -> arbiter -> book -> strategy -> risk -> dashboard)
# with the simulation VGA stub. Writes out/orders.txt and out/frame.hex, then run:
#   python ../python/e2e.py ../mem/market_data.hex out
file mkdir out
vlib work
vlog ../rtl/market_rom.v ../rtl/feed_handler.v ../rtl/prio_enc64.v ../rtl/order_book.v ../rtl/seg7.v \
     ../rtl/sync2.v ../rtl/strategy.v ../rtl/risk_gate.v ../rtl/dashboard.v \
     ../rtl/order_arbiter.v ../rtl/matching_engine.v ../rtl/ps2_rx.v ../rtl/kb_decoder.v \
     ../rtl/bin2bcd.v ../rtl/order_entry.v ../rtl/hft_top.v \
     ../tb/mocks/vga_adapter.v ../tb/hft_top_tb.v
vsim work.hft_top_tb
add wave /hft_top_tb/clk
add wave -divider "tick to trade"
add wave /hft_top_tb/dut/msg_start /hft_top_tb/dut/book_done /hft_top_tb/dut/quote_valid /hft_top_tb/dut/order_valid
add wave -radix unsigned /hft_top_tb/dut/best_bid /hft_top_tb/dut/best_ask
add wave -radix unsigned /hft_top_tb/dut/our_bid_px /hft_top_tb/dut/our_ask_px
add wave -divider "dashboard"
add wave -radix unsigned /hft_top_tb/dut/u_dash/state /hft_top_tb/dut/u_dash/level /hft_top_tb/dut/vga_x /hft_top_tb/dut/vga_y /hft_top_tb/dut/vga_colour /hft_top_tb/dut/vga_plot
run -all
