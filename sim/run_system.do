# ModelSim: M2 system test of hft_top vs python/system_model.py
# First (from sim/):
#   python ../python/system_model.py ../mem/market_data.hex kb_script.txt sys_expected.txt --hs 1 --kb-hex vectors/sys_kb.hex
# Then:  do run_system.do
# Then:  python ../python/sys_compare.py sys_expected.txt sys_out.txt
vlib work
vlog ../rtl/market_rom.v ../rtl/feed_handler.v ../rtl/prio_enc64.v ../rtl/order_book.v ../rtl/seg7.v \
     ../rtl/sync2.v ../rtl/strategy.v ../rtl/risk_gate.v ../rtl/pnl_tracker.v \
     ../rtl/font_rom.v ../rtl/bin2bcd.v ../rtl/dashboard.v \
     ../rtl/order_arbiter.v ../rtl/matching_engine.v ../rtl/ps2_rx.v ../rtl/kb_decoder.v \
     ../rtl/bin2bcd_comb.v ../rtl/order_entry.v ../rtl/hft_top.v \
     ../tb/mocks/vga_adapter.v ../tb/hft_system_tb.v
vsim work.hft_system_tb
add wave /hft_system_tb/clk /hft_system_tb/KEY /hft_system_tb/ps2_clk /hft_system_tb/ps2_dat
add wave -divider "Sources -> arbiter -> book"
add wave /hft_system_tb/dut/msg_valid /hft_system_tb/dut/f_ready /hft_system_tb/dut/k_valid /hft_system_tb/dut/k_ready
add wave -radix unsigned /hft_system_tb/dut/arb_state /hft_system_tb/dut/arb_owner -radix hex /hft_system_tb/dut/arb_id
add wave /hft_system_tb/dut/book_done -radix unsigned /hft_system_tb/dut/best_bid /hft_system_tb/dut/best_ask
add wave -divider "Trade -> fill"
add wave /hft_system_tb/dut/trade_valid /hft_system_tb/dut/trade_side -radix unsigned /hft_system_tb/dut/trade_price /hft_system_tb/dut/trade_qty
add wave /hft_system_tb/dut/fill_valid /hft_system_tb/dut/fill_side -radix unsigned /hft_system_tb/dut/fill_px /hft_system_tb/dut/fill_qty /hft_system_tb/dut/fill_count
add wave -divider "Our quotes"
add wave /hft_system_tb/dut/order_valid /hft_system_tb/dut/our_bid_live -radix unsigned /hft_system_tb/dut/our_bid_px
add wave /hft_system_tb/dut/our_ask_live -radix unsigned /hft_system_tb/dut/our_ask_px /hft_system_tb/dut/bid_rem /hft_system_tb/dut/ask_rem
add wave -divider "Keyboard"
add wave -radix unsigned /hft_system_tb/dut/entry_state -radix hex /hft_system_tb/dut/k_msg -radix unsigned /hft_system_tb/dut/kb_sent /hft_system_tb/dut/kb_errs
run -all
