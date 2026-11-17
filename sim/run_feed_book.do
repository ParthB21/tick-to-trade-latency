# ModelSim: ROM -> feed handler -> order book, full market data at full speed
# Writes sim_out.txt; then run:  python ../python/compare.py expected.txt sim_out.txt
# For the 13-message test instead, change the vsim line to:
#   vsim -gMEM_FILE=../mem/test_small.hex -gOUT_FILE=sim_out_small.txt work.feed_book_tb
vlib work
vlog ../rtl/market_rom.v ../rtl/feed_handler.v ../rtl/prio_enc64.v ../rtl/order_book.v ../tb/feed_book_tb.v
vsim work.feed_book_tb
add wave -divider "ROM"
add wave /feed_book_tb/clk /feed_book_tb/resetn
add wave -radix unsigned /feed_book_tb/rom_addr
add wave -radix hex /feed_book_tb/rom_q
add wave -divider "Feed handler"
add wave -radix unsigned /feed_book_tb/feed_state /feed_book_tb/msg_start /feed_book_tb/msg_valid
add wave -radix unsigned /feed_book_tb/msg_type /feed_book_tb/msg_side /feed_book_tb/msg_price /feed_book_tb/msg_id /feed_book_tb/msg_qty
add wave -radix unsigned /feed_book_tb/msg_count /feed_book_tb/feed_end
add wave -divider "Order book"
add wave -radix unsigned /feed_book_tb/book_state /feed_book_tb/book_ready /feed_book_tb/book_done
add wave -radix unsigned /feed_book_tb/best_bid /feed_book_tb/bid_valid /feed_book_tb/best_ask /feed_book_tb/ask_valid
add wave -radix unsigned /feed_book_tb/trade_valid /feed_book_tb/trade_side /feed_book_tb/trade_price /feed_book_tb/trade_qty
run -all
wave zoom range 20400ns 22000ns
