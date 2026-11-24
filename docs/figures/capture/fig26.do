do ../docs/figures/capture/tail.do
do run_system.do
delete wave /hft_system_tb/KEY /hft_system_tb/ps2_clk /hft_system_tb/ps2_dat
delete wave /hft_system_tb/dut/entry_state /hft_system_tb/dut/k_msg /hft_system_tb/dut/kb_sent /hft_system_tb/dut/kb_errs
add wave -divider {P&L tracker}
add wave -radix decimal /hft_system_tb/dut/position /hft_system_tb/dut/pnl
restart -f
run -all
cap_layout 2391500ns 2391800ns 2200 900
cap_ready
