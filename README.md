# Tick-to-Trade on a Chip

A small electronic market maker on a DE1-SoC FPGA. A ROM holds 1000 recorded market
messages. The chip replays them through an order book, works out a two-sided quote,
checks it against risk limits, and sends it out, all in 7 to 8 clock cycles (140 to 160 ns
at 50 MHz). The order book and our quotes are drawn live on a VGA monitor.

```
ROM -> feed handler -> order book -> strategy -> risk gate -> orders
                           |                         |
                           +------> dashboard <------+------> VGA
```

Everything in `rtl/` is Verilog that goes on the board. Everything in `python/` runs on a
laptop only: it generates the market data, computes the correct answers, and checks the
simulations against them.

## Folders

| Folder | What's in it |
|---|---|
| `rtl/` | The hardware. Plain Verilog-2001, one 50 MHz clock, no `/` or `%`. |
| `tb/` | Testbenches. `tb/mocks/` holds a simulation-only VGA stub. |
| `python/` | Data generator and reference models used to check the hardware. |
| `mem/` | ROM contents: `market_data` (1000 messages) and `test_small` (13 messages), as `.hex`, `.mif` and `.csv`. |
| `sim/` | ModelSim `.do` scripts, an Icarus script that runs the whole trading pipeline, and expected outputs. |
| `quartus/` | Quartus project folder. `milestone1.sdc` sets the 50 MHz clock constraint. |

## Message format

One 32-bit ROM word per message:

```
[31:30] type      00 ADD   01 CANCEL   10 TRADE   11 END
[29]    side      0 bid    1 ask
[28:23] price     0..63
[22:13] order ID  0..1023
[12:0]  qty       0..8191
```

## Hardware (`rtl/`)

**Market side**

| File | What it does |
|---|---|
| `market_rom.v` | 1024 x 32 ROM loaded from a `.hex` file. 1-cycle read. |
| `feed_handler.v` | Reads one message per `go` pulse and hands it to the book. Stops at END. |
| `order_book.v` | Keeps every resting order and the total quantity at each price level, with a 64-bit mask per side marking non-empty levels. Clears its RAMs after reset (1024 cycles). ADD takes 4 cycles, CANCEL and TRADE take 5. Pulses `done` when best bid/ask are up to date. Has a query port (`q_side`, `q_level` -> `q_qty`, 1-cycle latency) for reading any level. |
| `prio_enc64.v` | Finds the best bid (highest set bit) and best ask (lowest set bit) from the masks. |

**Trading side**

| File | What it does |
|---|---|
| `strategy.v` | Market-making quote. On each `done` it snapshots the top of book and our position, takes the mid, and quotes `floor(mid) - half_spread - skew` and `ceil(mid) + half_spread - skew`, clamped to 0..63. `skew = position * skew_k / 8` ticks (a multiplier, rounded toward zero), so when we are long both quotes drop and we sell more easily. Works in half-ticks (`bid + ask`) so there are no fractions. Signed 12-bit maths so a quote below 0 clamps to 0 instead of wrapping. 2 cycles. |
| `risk_gate.v` | Checks each side of the quote in parallel: size limit, position limits, and that it doesn't cross the market. A side that fails is pulled, the other can still go out. Kill switch latches until reset and pulls both sides. Sticky reject flags for the LEDs. 1 cycle. |
| `pnl_tracker.v` | Position and P&L accumulators. Each fill adds or subtracts shares and `px * qty` cash; P&L = cash + position x mark, where the mark is the floor of the mid. Feeds position back to the strategy (skew) and the risk gate (limits). |
| `dashboard.v` | Draws the book on VGA as a ladder: one row pair per price, green bars for bids, red for asks, yellow markers for our quotes. Below it, `POS +ddd` in white and `PNL +ddddd` in green (red when negative). It repaints every pixel continuously instead of erasing, so old bars and digits disappear on their own. A full frame takes 1.5 ms. |
| `font_rom.v` | 5x7 glyphs for the digits, `+`, `-` and the letters of POS / PNL. Drawn 2x on screen. |
| `bin2bcd.v` | Binary to decimal digits by shift-and-add-3, one bit per clock (no divider). |

**Shared and top level**

| File | What it does |
|---|---|
| `sync2.v` | Two-flop synchroniser for switches and keys. |
| `seg7.v` | 7-segment decoder (digits, dash, blank). |
| `milestone1_top.v` | Market-side board top: the book on the HEX displays, with a level inspector. |
| `hft_top.v` | Full board top: the whole pipeline plus VGA, HEX and LEDs. |

## Python (`python/`)

| File | What it does |
|---|---|
| `msgfmt.py` | Packs and unpacks the 32-bit message format. |
| `gen_market.py` | Generates `mem/market_data.*` and `mem/test_small.*`. |
| `ref_model.py` | Order book model. Writes the expected best bid/ask after every message. |
| `compare.py` | Diffs the book simulation against `ref_model.py`. |
| `strategy.py`, `risk.py`, `pnl.py`, `dashboard.py` | Models of the strategy, risk gate, P&L tracker and VGA frame. |
| `check_dashboard.py` | Checks the dashboard testbench's frames (fake book, several position / P&L cases) pixel by pixel. |
| `gen_vectors.py` | Writes the random and edge-case test vectors in `sim/vectors/`. |
| `e2e.py` | Chains book -> strategy -> risk in Python, then checks every order and every VGA pixel from the full simulation. Writes `expected.png` and `sim.png` to compare by eye. |

## Running the simulations

**Trading pipeline (Icarus Verilog)**, from the repo root:

```
sim/run_all.sh
```

This regenerates the vectors, runs the strategy, risk gate, P&L tracker, dashboard and
full-board testbenches, then runs `e2e.py`. Output goes to `sim/out/`. Current results:

- strategy: 221 vectors pass (including inventory skew at +-511/-512), 2-cycle latency checked on each
- risk gate: 244 cycles pass, every reject flag exercised
- P&L tracker: 521 cycles pass, position reaching +-510
- dashboard: 3 frames (negative, clamped, zero and -512 values) match pixel for pixel
- full board: 1000/1000 orders and 76,800/76,800 frame pixels match the Python chain
- tick-to-trade: 7 to 8 cycles; the first message after reset takes 1028 because of the RAM clear

**ModelSim**, from `sim/`:

| Command | What it runs |
|---|---|
| `do run_order_book.do` | The book on its own, 23 directed checks. |
| `do run_feed_book.do` | ROM -> feed -> book over all 1000 messages. Writes `sim_out.txt`. |
| `do run_top.do` | `milestone1_top`, printing the HEX displays after each key press. |
| `do run_strategy.do`, `do run_risk_gate.do`, `do run_pnl_tracker.do` | Strategy, risk gate and P&L tracker against their vectors. |
| `do run_dashboard.do` | Dashboard with a fake book. Then run `python ../python/check_dashboard.py out`. |
| `do run_hft_top.do` | Full board. Then run `python ../python/e2e.py ../mem/market_data.hex out`. |

To check the book against Python: `python ../python/compare.py expected.txt sim_out.txt`.

To regenerate the market data (only if the generator changes):

```
cd python
python gen_market.py
python ref_model.py ../mem/market_data.hex ../sim/expected.txt
python ref_model.py ../mem/test_small.hex ../sim/expected_small.txt
```

## Putting it on the board

1. Open or create the project in `quartus/`, device 5CSEMA5F31C6, and add `milestone1.sdc`.
2. Set the top-level entity to `hft_top` (full system) or `milestone1_top` (book only).
3. Add every file in `rtl/`, never `tb/`. For `hft_top`, also add the course VGA files
   (`vga_adapter.v`, `vga_controller.v`, `vga_address_translator.v`, `vga_pll.v`) and `black.mif`.
4. Import the course `DE1_SoC.qsf` pin assignments.
5. The ROM loads `../mem/*.hex` relative to the project folder, so keep the layout.
6. Compile, check timing at 50 MHz, program, press KEY[0].

## Controls: `hft_top`

| Input | Does |
|---|---|
| KEY[0] | Reset |
| KEY[1] | One message per press (when SW[1:0] = 00) |
| SW[1:0] | 00 step, 01 auto (4 messages/s), 1x full speed |
| SW[2] | Inventory skew on (quotes shift 1 tick per 4 shares held) |
| SW[4:3] | Quote size 1 / 2 / 4 / 8 |
| SW[6:5] | Half-spread 0..3 ticks |
| SW[8:7] | Max position 4 / 8 / 16 / 32 |
| SW[9] | Kill switch (latches until reset) |

HEX5-4 shows our bid, HEX3-2 our ask (`--` when that side isn't live). LEDR[9] killed,
LEDR[8] feed finished, LEDR[7]/[6] ask/bid live, LEDR[5:0] reject flags
(5 cross, 4 short limit, 3 long limit, 2 size, 1 one-sided book, 0 kill).

Nothing fills our orders until the matching engine is connected, so position and P&L stay
at zero on the board and skew has no effect yet. The position limits still fire on the board
when the quote size is bigger than the max position (SW[4:3] = 11 with SW[8:7] = 00).

**Fill interface** (matching engine -> `pnl_tracker`, wired in `hft_top.v`):
`fill_valid` (1-cycle pulse), `fill_side` (0 = our bid hit, we bought; 1 = our ask lifted,
we sold), `fill_px[5:0]`, `fill_qty[7:0]`.

## Controls: `milestone1_top`

| Input | Does |
|---|---|
| KEY[0] | Reset |
| KEY[1] | Process one message |
| SW[9] | Auto-play (4 messages/s) |
| SW[8] | 0 = 13-message test data, 1 = full market (press KEY[0] after switching) |
| SW[7] | 0 = market view, 1 = level view |
| SW[6] | Level view side (0 bid, 1 ask) |
| SW[5:0] | Level view price |

Market view: HEX5-4 best bid, HEX3-2 best ask, HEX1-0 message count. Level view: HEX5-4
the price, HEX3-0 the quantity there.

LEDR[9] bids exist, LEDR[8] asks exist, LEDR[7] feed finished, LEDR[6] book busy,
LEDR[5] last message was a trade, LEDR[4] last side (on = ask), LEDR[3:2] last type,
LEDR[0] auto-play.

With the test data, stepping with KEY[1] should show (bid, ask, count):

| Step | Message | HEX |
|---|---|---|
| 1 | ADD bid 100 @ 10 | `10 -- 01` |
| 2 | ADD bid 50 @ 12 | `12 -- 02` |
| 3 | ADD ask 70 @ 15 | `12 15 03` |
| 4 | ADD ask 30 @ 14 | `12 14 04` |
| 5 | ADD bid 25 @ 12 | `12 14 05` |
| 6 | CANCEL order 2 (12 still has 25) | `12 14 06` |
| 7 | TRADE 10 of order 4 @ 14 | `12 14 07` |
| 8 | TRADE 20 of order 4 (14 now empty) | `12 15 08` |
| 9 | CANCEL order 5 (12 now empty) | `10 15 09` |
| 10 | CANCEL unknown order 99 (ignored) | `10 15 10` |
| 11 | ADD bid 40 @ 13 | `13 15 11` |
| 12 | CANCEL order 6 | `10 15 12` |
| 13 | CANCEL order 1 (no bids left) | `-- 15 13` |
| 14 | END | LEDR[7] on |
