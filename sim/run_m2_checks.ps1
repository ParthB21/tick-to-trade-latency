# Runs every M2 check in batch mode (no GUI) and prints the result lines.
# From the sim folder in PowerShell:   .\run_m2_checks.ps1
# (If scripts are blocked: powershell -ExecutionPolicy Bypass -File .\run_m2_checks.ps1)
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force out, vectors | Out-Null

function Run-Sim($title, $files, $tbname, $extra) {
    Write-Host "==== $title ====" -ForegroundColor Cyan
    vlib work | Out-Null
    vlog -quiet @files | Out-Null
    vsim -c @extra $tbname -do "run -all; quit -f" | Select-String -Pattern "PASS|FAIL|ALL PASS|processed|throughput|replay|done at|TIMEOUT|Error:"
}

python ../python/gen_match_vectors.py
python ../python/gen_entry_vectors.py
python ../python/ref_model.py ../mem/market_data.hex expected.txt
python ../python/system_model.py ../mem/market_data.hex kb_script.txt sys_expected.txt --hs 1 --kb-hex vectors/sys_kb.hex
python ../python/system_model.py ../mem/market_data.hex kb_script.txt sys_expected_hs0.txt --hs 0
python ../python/system_model.py ../mem/test_small.hex kb_demo_small.txt sys_expected_demo.txt --hs 1 --kb-hex vectors/demo_kb.hex

$rtl = "../rtl/market_rom.v","../rtl/feed_handler.v","../rtl/prio_enc64.v","../rtl/order_book.v","../rtl/seg7.v",
       "../rtl/sync2.v","../rtl/strategy.v","../rtl/risk_gate.v","../rtl/dashboard.v",
       "../rtl/order_arbiter.v","../rtl/matching_engine.v","../rtl/ps2_rx.v","../rtl/kb_decoder.v",
       "../rtl/bin2bcd.v","../rtl/order_entry.v","../rtl/hft_top.v","../tb/mocks/vga_adapter.v"

Run-Sim "order book (M1 + source bit)" @("../rtl/prio_enc64.v","../rtl/order_book.v","../tb/order_book_tb.v") "work.order_book_tb" @()
Run-Sim "feed + book, 1000 messages" @("../rtl/market_rom.v","../rtl/feed_handler.v","../rtl/prio_enc64.v","../rtl/order_book.v","../tb/feed_book_tb.v") "work.feed_book_tb" @()
python ../python/compare.py expected.txt sim_out.txt
Run-Sim "matching engine" @("../rtl/matching_engine.v","../tb/matching_engine_tb.v") "work.matching_engine_tb" @()
Run-Sim "order arbiter" @("../rtl/order_arbiter.v","../tb/order_arbiter_tb.v") "work.order_arbiter_tb" @()
Run-Sim "keyboard path" @("../rtl/ps2_rx.v","../rtl/kb_decoder.v","../rtl/bin2bcd.v","../rtl/order_entry.v","../tb/order_entry_tb.v") "work.order_entry_tb" @()
Run-Sim "hft_top (Pierce's e2e)" ($rtl + "../tb/hft_top_tb.v") "work.hft_top_tb" @()
python ../python/e2e.py ../mem/market_data.hex out
Run-Sim "system, half-spread 1" ($rtl + "../tb/hft_system_tb.v") "work.hft_system_tb" @()
python ../python/sys_compare.py sys_expected.txt sys_out.txt
Run-Sim "system, half-spread 0" ($rtl + "../tb/hft_system_tb.v") "work.hft_system_tb" @("-gHS=0", "-gOUT_FILE=sys_out_hs0.txt")
python ../python/sys_compare.py sys_expected_hs0.txt sys_out_hs0.txt

Run-Sim "board demo sequence (13-message test data + keyboard)" ($rtl + "../tb/hft_system_tb.v") "work.hft_system_tb" @("-gMARKET_HEX=../mem/test_small.hex", "-gKB_HEX=vectors/demo_kb.hex", "-gOUT_FILE=sys_out_demo.txt")
python ../python/sys_compare.py sys_expected_demo.txt sys_out_demo.txt
