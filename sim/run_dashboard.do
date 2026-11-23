# ModelSim: dashboard.v with a fake book and the VGA stub, 3 position / P&L cases.
# Writes out/dash_<n>.hex, then run:  python ../python/check_dashboard.py out
file mkdir out
vlib work
vlog ../rtl/font_rom.v ../rtl/bin2bcd.v ../rtl/dashboard.v ../tb/mocks/vga_adapter.v ../tb/dashboard_tb.v
vsim work.dashboard_tb
add wave /dashboard_tb/clk -radix unsigned /dashboard_tb/dut/state /dashboard_tb/x /dashboard_tb/y /dashboard_tb/colour /dashboard_tb/plot
add wave -radix decimal /dashboard_tb/position /dashboard_tb/pnl
add wave -radix hex /dashboard_tb/dut/pos_bcd /dashboard_tb/dut/pnl_bcd
add wave -radix unsigned /dashboard_tb/dut/slot /dashboard_tb/dut/glyph /dashboard_tb/dut/grow -radix binary /dashboard_tb/dut/font_bits
run -all
