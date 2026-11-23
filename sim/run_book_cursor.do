vlib work
vlog ../rtl/prio_enc64.v ../rtl/book_cursor.v ../tb/book_cursor_tb.v
vsim work.book_cursor_tb
add wave /book_cursor_tb/clk /book_cursor_tb/resetn
add wave /book_cursor_tb/key_valid -radix unsigned /book_cursor_tb/key_code
add wave -radix hex /book_cursor_tb/bid_mask /book_cursor_tb/ask_mask
add wave -radix unsigned /book_cursor_tb/dut/up_idx /book_cursor_tb/dut/down_idx /book_cursor_tb/cursor
run -all
