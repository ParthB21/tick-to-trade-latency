# ModelSim: keyboard path on its own: PS/2 frames -> ps2_rx -> kb_decoder -> order_entry
# Regenerate vectors first if needed:  python ../python/gen_entry_vectors.py
vlib work
vlog ../rtl/ps2_rx.v ../rtl/kb_decoder.v ../rtl/bin2bcd.v ../rtl/order_entry.v ../tb/order_entry_tb.v
vsim work.order_entry_tb
add wave -divider "PS/2 pins"
add wave /order_entry_tb/ps2_clk /order_entry_tb/ps2_dat
add wave -divider "ps2_rx"
add wave /order_entry_tb/u_rx/fall -radix unsigned /order_entry_tb/u_rx/nbits -radix binary /order_entry_tb/u_rx/sh
add wave /order_entry_tb/rx_valid -radix hex /order_entry_tb/rx_byte /order_entry_tb/frame_err
add wave -divider "kb_decoder"
add wave /order_entry_tb/u_dec/brk /order_entry_tb/u_dec/ext /order_entry_tb/key_valid -radix unsigned /order_entry_tb/key_code
add wave -divider "order_entry"
add wave -radix unsigned /order_entry_tb/entry_state /order_entry_tb/u_entry/mode -radix hex /order_entry_tb/u_entry/dig
add wave -radix unsigned /order_entry_tb/u_entry/ndig /order_entry_tb/u_entry/num1 /order_entry_tb/u_entry/value
add wave /order_entry_tb/k_valid /order_entry_tb/k_ready -radix hex /order_entry_tb/k_msg
add wave -radix unsigned /order_entry_tb/next_id /order_entry_tb/sent_count /order_entry_tb/err_count
run -all
# first typed line "B12 50 Enter" (18 PS/2 bytes, one message out)
wave zoom range 0ns 960us

virtual type {CMD NUM1 NUM2 SEND} entry_state_t
virtual function -install /order_entry_tb {(entry_state_t)/order_entry_tb/entry_state} entry_state_name
virtual type {BUY SELL CANCEL TRADE} entry_mode_t
virtual function -install /order_entry_tb {(entry_mode_t)/order_entry_tb/u_entry/mode} entry_mode_name
add wave -position 11 /order_entry_tb/entry_state_name /order_entry_tb/entry_mode_name
