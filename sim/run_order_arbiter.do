# ModelSim: order arbiter on its own (collision cases + 360-message stress test)
vlib work
vlog ../rtl/order_arbiter.v ../tb/order_arbiter_tb.v
vsim work.order_arbiter_tb
add wave /order_arbiter_tb/clk
add wave -divider "Feed (source 0)"
add wave /order_arbiter_tb/f_valid -radix unsigned /order_arbiter_tb/f_tag /order_arbiter_tb/f_ready /order_arbiter_tb/f_done
add wave -divider "Keyboard (source 1)"
add wave /order_arbiter_tb/k_valid -radix unsigned /order_arbiter_tb/k_tag /order_arbiter_tb/k_ready /order_arbiter_tb/k_done
add wave -divider "Arbiter"
add wave -radix unsigned /order_arbiter_tb/arb_state /order_arbiter_tb/owner
add wave -divider "Book"
add wave /order_arbiter_tb/b_valid /order_arbiter_tb/b_ready -radix hex /order_arbiter_tb/b_id /order_arbiter_tb/b_done
run -all
# case 1 (same cycle) 90-350 ns, case 2 (kbd while busy) 430-790 ns, case 3 (back-to-back) 870-1470 ns
wave zoom range 80ns 1480ns

virtual type {IDLE FEED KBD} arb_state_t
virtual function -install /order_arbiter_tb {(arb_state_t)/order_arbiter_tb/arb_state} arb_state_name
add wave -position 11 /order_arbiter_tb/arb_state_name
