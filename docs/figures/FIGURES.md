# Milestone 2 report figures

Every image here was produced from the RTL, testbenches and scripts as they are on `main` at
commit `4d9b429` (after the risk-gate fix, ParthB21/tick-to-trade-latency#4). No RTL, testbench or `.do` file was changed to
make a figure. All simulations ran in ModelSim Intel FPGA Starter Edition 10.5b
(Quartus Prime Lite 18.1), from `sim/`.

How the images were made:

- **Waveforms** use [capture/capture.ps1](capture/capture.ps1) (Windows; run from `sim/`).
  - **Run:** it opens the ModelSim GUI on `capture/figNN.do`, which runs the unchanged `sim/run_*.do`. The wrapper then undocks the Wave window and sets short signal names (`configure wave -signalnamewidth 1`). It applies `wave zoom range` and adds any signal a caption needs that the `.do` script does not have, listed below.
  - **Added signals:** these are added after the `.do` has run, so the wrapper then runs `restart -f; run -all` so that ModelSim logs them from t = 0.
  - **`$finish`:** testbenches that end in `$finish` run with a copy of `modelsim.ini` set to `OnFinish = stop`, so the GUI does not stop on a dialog.
  - **Capture:** the Wave window is captured and cropped to the wave pane ([capture/crop.py](capture/crop.py)).
  - **Reading the "Msgs" column:** it shows each signal's value at the **end** of the simulation ("Now" in the bottom-left box), not at the zoomed time. Read the values on the waves.
- **Test transcripts** come from running each testbench in batch mode: `vsim -c work.<tb> -do "run -all; quit -f"`, after compiling the same file list as its `.do` script.
  - The full output was saved, and [transcript_to_png.py](transcript_to_png.py) renders the relevant lines as terminal-style PNGs.
  - The text is copied verbatim from the logs, and the command above each block is the one that produced it.
- **VGA frame**: [frame_to_png.py](frame_to_png.py).
- **Diagrams**: [make_m2_figures.py](make_m2_figures.py) (`python make_m2_figures.py` in this folder).

## A. ModelSim waveforms

| Fig | File | Command | Zoom used | Differences from the caption / notes |
|---|---|---|---|---|
| 2 | [fig02_book_masks.png](fig02_book_masks.png) | `do run_order_book.do` ([capture/fig02.do](capture/fig02.do)) | 41,000–42,800 ns (as captioned) | None in the values. `state` = 6 is LVL_UPD. At this zoom the `book_state` names do not fit, so only the numbers show. `bid_mask`/`ask_mask` and `best_bid`/`best_ask` change together on the clock edge that ends LVL_UPD (state 6 → 7 DONE). |
| 2b (extra) | [fig02b_book_masks_zoom.png](fig02b_book_masks_zoom.png) | same ([capture/fig02b.do](capture/fig02b.do)) | 41,000–41,280 ns | Close-up of the first two adds with the state names readable. `bid_mask` 0 → …0400 and `best_bid` 0 → 10 at about 41,090 ns, then …1400 and 12 at about 41,190 ns. Both happen on the LVL_UPD → DONE edge. |
| 5 | [fig05_matching_bid30.png](fig05_matching_bid30.png) | `do run_matching_engine.do` ([capture/fig05.do](capture/fig05.do)) | 60–400 ns (as captioned) | None. Quote at 80 ns: bid 30 × 4. Trade @30 qty 10 → fill 4 @30 at 130 ns, `bid_rem` 4 → 0. A trade @29 then does not fill (nothing left). Requote at 200 ns. Trade @31 does not fill. Trade @28 → fill 1 @30 at about 290 ns, `bid_rem` 3. |
| 7 | [fig07_arbiter_case1.png](fig07_arbiter_case1.png) | `do run_order_arbiter.do` ([capture/fig07.do](capture/fig07.do)) | 80–360 ns (as captioned) | None. `f_valid` and `k_valid` rise together at 100 ns. KBD is granted at 110 ns (`b_id` = 6bc = {1, 700}). `f_valid` stays high until the feed message is accepted at 210 ns (`b_id` = 002). `k_done` comes only in KBD, `f_done` only in FEED. |
| 8 | [fig08_arbiter_case2.png](fig08_arbiter_case2.png) | same ([capture/fig08.do](capture/fig08.do)) | 420–800 ns (as captioned) | None. F4 is accepted at 450 ns. K702 arrives at 480 ns while the book is busy and is accepted at 550 ns, right after F4's done. F6 is accepted at 650 ns. |
| 9 | [fig09_arbiter_case3.png](fig09_arbiter_case3.png) | same ([capture/fig09.do](capture/fig09.do)) | 860–1,480 ns (as captioned) | None. Order: F8, K704, F10, K706, F12, F14 (accepted at 890 / 990 / 1090 / 1190 / 1290 / 1390 ns). `f_done` pulses only to the feed, `k_done` only to the keyboard. |
| 11 | [fig11_ps2_frame.png](fig11_ps2_frame.png) | `do run_order_entry.do` ([capture/fig11.do](capture/fig11.do)) | 0–50 µs | No caption range was given. The frame starts at about 1 µs: start bit, 8 data bits, parity, stop. `rx_valid` with `rx_byte` = 32 comes at about 43 µs, then `key_code` = 10 (B) and CMD → NUM1. |
| 12 | [fig12_typing_b12_50.png](fig12_typing_b12_50.png) | same ([capture/fig12.do](capture/fig12.do)) | **0–1,000 µs** (caption: 0–960 µs) | **Range differs.** The Enter key arrives after 960 µs: `k_valid` rises at **979.13 µs** with `k_msg` = 06002032, and `k_ready` comes at 979.27 µs. The zoom was widened to 1 ms. At this zoom the 140 ns handshake is about one pixel and `k_msg` is cut off at the right edge, so fig 12b shows it. |
| 12b (extra) | [fig12b_entry_send.png](fig12b_entry_send.png) | same ([capture/fig12b.do](capture/fig12b.do)) | 978,900–979,400 ns | Enter (`key_code` 15) → SEND, `k_valid` = 1, `k_msg` = 06002032. `k_ready` follows 7 cycles later, then back to CMD (`next_id` 2, `sent_count` 1). |
| 18 | [fig18_pnl_buy_sell.png](fig18_pnl_buy_sell.png) | `do run_pnl_tracker.do` ([capture/fig18.do](capture/fig18.do)) | 60–280 ns | Buy 4 @30 (`fill_valid` 100–120 ns): `position` 0 → 4 and `cash` 0 → −120 at the 110 ns edge, which samples `fill_valid`. `pnl` follows one clock later at 130 ns: −120, then +4 at 150 ns when `mark` updates. Sell 4 @33 (200–220 ns): `position` 4 → 0 and `cash` → +12 at 210 ns, `pnl` 12 at 230 ns. The testbench drives `fill_valid` on the falling edge, so "the cycle after fill_valid" is the rising edge that samples it. |
| 20 | [fig20_strategy_skew.png](fig20_strategy_skew.png) | `do run_strategy.do`, plus `add wave dut/s_pos dut/s_k` ([capture/fig20.do](capture/fig20.do)) | 740–900 ns | **Notes, not a mismatch.** The vector is the one at trigger 820 ns: position +8, `skew_k` 2, book 30/33, half-spread 1 → `skew` = 2, quote 28/31. The vector just before it (760 ns) has the same book and position with `skew_k` 0 → quote 30/33, so both sides are 2 ticks lower. `quote_valid` comes 2 cycles after trigger (850 ns). The testbench scrambles the live inputs (`~vin`) right after trigger, to prove the FSM uses its snapshot, so the `position` and `skew_k` rows change right after each trigger. The snapshot registers `s_pos` = 8 and `s_k` = 2 were added to show the values actually used. |
| 26 | [fig26_system_fill_timing.png](fig26_system_fill_timing.png) | `python ../python/system_model.py ../mem/market_data.hex kb_script.txt sys_expected.txt --hs 1 --kb-hex vectors/sys_kb.hex`, then `do run_system.do`, plus `add wave dut/position dut/pnl` ([capture/fig26.do](capture/fig26.do)) | 2,391,500–2,391,800 ns | None in the timing. This is the first fill of the run: a trade bid @31 qty 162 against our bid 31 × 2. d = 2,391,660 ns (`book_done` and `trade_valid`). `fill_valid` (BUY 2 @31) at d+1, `position` 0 → 2 at d+2, `order_valid` at d+3 (requote, bid 30). The keyboard and PS/2 rows of `run_system.do` were removed from the view to make room; the empty "Keyboard" divider is left over. |

## B. Test transcripts

| Fig | File | Command(s) | Result | Differences from the caption |
|---|---|---|---|---|
| 3 | [fig03_order_book_tests.png](fig03_order_book_tests.png) | `vsim -c work.order_book_tb` (files of `run_order_book.do`) | 27 checks passed, 0 failed | None |
| 6 | [fig06_matching_tests.png](fig06_matching_tests.png) | `python ../python/gen_match_vectors.py`; `vsim -c work.matching_engine_tb` | 13/13 named checks, 500/500 vectors, 103 fills | None |
| 10 | [fig10_arbiter_tests.png](fig10_arbiter_tests.png) | `vsim -c work.order_arbiter_tb` | 6 checks passed. Sent 307 feed + 64 kbd = 371, book received 371, misrouted 0 | None |
| 13 | [fig13_order_entry_tests.png](fig13_order_entry_tests.png) | `python ../python/gen_entry_vectors.py`; `vsim -c work.order_entry_tb` | 10 checks passed: 12 messages, 9 rejects, 1 bad-parity frame, 7 display checks | None |
| 14 | [fig14_system_hs1.png](fig14_system_hs1.png) | `system_model.py … sys_expected.txt --hs 1 --kb-hex vectors/sys_kb.hex`; `vsim -c work.hft_system_tb`; `sys_compare.py sys_expected.txt sys_out.txt` | 1010 messages (1000 ROM + 10 keyboard), 34 fills, PASS | None |
| 19 | [fig19_pnl_tests.png](fig19_pnl_tests.png) | `python ../python/gen_vectors.py`; `vsim -c work.pnl_tracker_tb` | PASS, 521 cycles, position −510..510 | None |
| 21 | [fig21_strategy_tests.png](fig21_strategy_tests.png) | `python ../python/gen_vectors.py`; `vsim -c work.strategy_tb` | PASS, **225 vectors** | 225, as the caption note expected (an older text said 221) |
| 24 | [fig24_e2e.png](fig24_e2e.png) | `vsim -c work.hft_top_tb` (file list of `sim/run_all.sh` and `run_m2_checks.ps1`); `python ../python/e2e.py ../mem/market_data.hex out` | 1000/1000 orders, 0 mismatches; frame 76,800 pixels, 0 mismatches; tick-to-trade 7..8 cycles | None |
| 25 | [fig25_system_skew.png](fig25_system_skew.png) | `system_model.py … sys_expected_skew.txt --hs 1 --skew-k 2`; `vsim -c -gSKEW=1 -gOUT_FILE=sys_out_skew.txt work.hft_system_tb`; `sys_compare.py sys_expected_skew.txt sys_out_skew.txt` | 1010 messages, 42 fills, PASS | None. `tb/hft_system_tb.v` has a `SKEW` parameter that drives SW[2], so no edit was needed. |

## C. Simulated VGA frame

| Fig | File | Command | Notes |
|---|---|---|---|
| 22 | [fig22_vga_frame.png](fig22_vga_frame.png) | `do run_dashboard.do` (run in batch with the same file list), then `python ../docs/figures/frame_to_png.py out/dash_0.hex ../docs/figures/fig22_vga_frame.png` | Case 0 of `dashboard_tb`: position −37, P&L −123,456, cursor on level 30. The panel shows `PNL -99999` because the dashboard clamps the P&L shown to 5 digits (`PNL_SHOWN`), and `check_dashboard.py` expects that (0 pixel mismatches in all 3 frames). Scaled from 320 × 240 to 1280 × 720, nearest-neighbour. |

## D. Diagrams

| Fig | File | Checked against | Change |
|---|---|---|---|
| 1 | [book_datapath.png](book_datapath.png) | `rtl/order_book.v`: otab 2048 × 21, level RAM 128 × 13, `lvl_view`/`lvl_view2` copies, masks + `prio_enc64` | Up to date, unchanged |
| 4 | [matching_datapath.png](matching_datapath.png) | `rtl/matching_engine.v`: `px >= p` / `px <= p`, `rem != 0`, reload on `order_valid`, `min(qty, rem)` | Up to date, unchanged |
| – | [arbiter_fsm.png](arbiter_fsm.png) | `rtl/order_arbiter.v`: IDLE / FEED / KBD, keyboard wins ties, done only to the owner | Up to date, unchanged |
| – | [entry_fsm.png](entry_fsm.png) | `rtl/order_entry.v`: CMD / NUM1 / NUM2 / SEND, Esc → CMD, Err on a failed check | Up to date, unchanged |
| – | [m2_block.png](m2_block.png) | `rtl/hft_top.v` | **Redrawn.** Added the arrow-key book cursor: `kb_decoder` up/down arrows → `book_cursor` (which also reads the book masks) → dashboard. The keyboard row moved above the ROM row to make room, and "depth" now reads "bid/ask depth". |
| – | [strategy_fsm.png](strategy_fsm.png) | `rtl/strategy.v`: S_IDLE → S_CALC → S_OUT → S_IDLE | **New** |
| – | [dashboard_fsm.png](dashboard_fsm.png) | `rtl/dashboard.v`, the state `case` in the main always block | **New.** ADDR_BID → ADDR_ASK → LATCH_ASK → DRAW, unconditionally. DRAW stays until x = 319 and dy = 2, then goes to ADDR_BID (level − 1), or to TEXT if level = 0. TEXT stays until x = 319 and y = 239, then goes to ADDR_BID. Reset → ADDR_BID. |
