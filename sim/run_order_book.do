# ModelSim: order book on its own (directed, self-checking)
# In ModelSim:  cd <project>/sim   then   do run_order_book.do
vlib work
vlog ../rtl/prio_enc64.v ../rtl/order_book.v ../tb/order_book_tb.v
vsim work.order_book_tb
add wave -divider "Message in"
add wave /order_book_tb/clk /order_book_tb/resetn /order_book_tb/in_valid /order_book_tb/in_ready
add wave -radix unsigned /order_book_tb/in_type /order_book_tb/in_side /order_book_tb/in_price /order_book_tb/in_id /order_book_tb/in_qty
add wave -divider "Book FSM"
add wave -radix unsigned /order_book_tb/dut/state /order_book_tb/done
add wave -radix unsigned /order_book_tb/dut/l_side /order_book_tb/dut/l_price /order_book_tb/dut/lvl_q /order_book_tb/dut/lvl_new
add wave -divider "Top of book"
add wave -radix unsigned /order_book_tb/best_bid /order_book_tb/bid_valid /order_book_tb/best_ask /order_book_tb/ask_valid
add wave -radix hex /order_book_tb/bid_mask /order_book_tb/ask_mask
add wave -divider "Trade event"
add wave -radix unsigned /order_book_tb/trade_valid /order_book_tb/trade_side /order_book_tb/trade_price /order_book_tb/trade_qty
add wave -divider "Query port"
add wave -radix unsigned /order_book_tb/q_side /order_book_tb/q_level /order_book_tb/q_qty
run -all
# skip the 41 us RAM clear (2048 addresses since M2) and zoom on the messages
wave zoom range 41000ns 42800ns

# Show FSM states by name (added after the run so a problem here never stops the sim)
virtual type {CLEAR IDLE ADD_TBL TBL_RD TBL_CHK LVL_RD LVL_UPD DONE} book_state_t
virtual function -install /order_book_tb {(book_state_t)/order_book_tb/dut/state} book_state
add wave -position 7 /order_book_tb/book_state