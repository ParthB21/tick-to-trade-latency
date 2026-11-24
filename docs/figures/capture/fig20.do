do ../docs/figures/capture/tail.do
do run_strategy.do
add wave -position 11 -radix decimal /strategy_tb/dut/s_pos
add wave -position 12 -radix unsigned /strategy_tb/dut/s_k
restart -f
run -all
cap_layout 740ns 900ns 2000 680
cap_ready
