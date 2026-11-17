# Tick-to-Trade on a Chip — Milestone 1 (Parth: market side)

ROM → feed handler → order book, shown on the HEX displays.
Everything in `rtl/` runs on the FPGA. Everything in `python/` runs on your laptop only
(makes the data, computes the correct answers, checks the simulation).

## Folders

| Folder | What's in it |
|---|---|
| `rtl/` | Verilog that goes on the board |
| `tb/` | Testbenches (ModelSim only) |
| `sim/` | ModelSim `.do` scripts + the Python model's expected answers |
| `mem/` | ROM contents: `market_data.*` (1000 msgs) and `test_small.*` (13 msgs) |
| `python/` | `gen_market.py`, `ref_model.py`, `compare.py`, `msgfmt.py` |
| `quartus/` | Make your Quartus project here |

## Message format (agree this with Pierce — it is fixed now)

One 32-bit ROM word per message:

```
[31:30] type   00 ADD   01 CANCEL   10 TRADE   11 END (stop)
[29]    side   0 BID    1 ASK
[28:23] price  0..63
[22:13] order ID 0..1023
[12:0]  qty    0..8191
```

## Modules

| File | What it does |
|---|---|
| `market_rom.v` | 1024 x 32 ROM loaded from a `.hex` file. 1-cycle read. |
| `feed_handler.v` | FSM: IDLE → READ → LATCH → SEND → WAIT → IDLE (or FINISHED on END). One message per `go` pulse. |
| `order_book.v` | FSM + 3 RAMs (order table 1024x21, level qty 128x13, level view copy 128x13) + two 64-bit masks. Clears its RAMs after reset (1024 cycles). ADD = 4 cycles, CANCEL/TRADE = 5 cycles. |
| `prio_enc64.v` | 64-bit priority encoder. Best bid = highest set bit, best ask = lowest. |
| `seg7.v` | 7-segment decoder (digits, dash, blank). |
| `milestone1_top.v` | Board top level for the demo. |

### Outputs Pierce's modules use from `order_book`
- `best_bid`, `bid_valid`, `best_ask`, `ask_valid` — top of book, updated by the time `done` pulses
- `q_side`, `q_level` → `q_qty` — read any level's quantity, valid 1 clock after the address (for the VGA depth bars)
- `bid_mask`, `ask_mask` — which levels are non-empty
- `trade_valid`, `trade_side`, `trade_price`, `trade_qty` — trade events (for the matching engine, M2)

Note: in `milestone1_top.v` the query port is driven by SW[6:0]. When the dashboard
is connected, give it the query port instead.

## Running the simulations (ModelSim)

In ModelSim: `cd` into `sim/`, then:

| Command | What it shows |
|---|---|
| `do run_order_book.do` | Book alone. Transcript prints PASS/FAIL for 23 checks. |
| `do run_feed_book.do` | ROM → feed → book over all 1000 messages. Writes `sim_out.txt`. |
| `do run_top.do` | The board top level; transcript prints what the HEX displays show after each KEY press. |

Then check the hardware against Python (from `sim/`):

```
python ../python/compare.py expected.txt sim_out.txt
```

Expected: `PASS: all 1000 messages match the Python reference model`

To regenerate the data (only if you change the generator):

```
cd python
python gen_market.py
python ref_model.py ../mem/market_data.hex ../sim/expected.txt
python ref_model.py ../mem/test_small.hex ../sim/expected_small.txt
```

## Putting it on the board (Quartus)

1. New project in the `quartus/` folder, device 5CSEMA5F31C6 (DE1-SoC), top-level entity `milestone1_top`.
2. Add every file in `rtl/`.
3. Import the course `DE1_SoC.qsf` pin assignments (port names match: CLOCK_50, KEY, SW, HEX0-5, LEDR).
4. The ROMs load `../mem/*.hex` relative to the project folder, so keep the folder layout.
5. Compile, program, then press KEY[0] once to reset.

## Board controls

| Input | Does |
|---|---|
| KEY[0] | Reset |
| KEY[1] | Process one message |
| SW[9] | Auto-play (4 messages/second) |
| SW[8] | 0 = 13-message test, 1 = 1000-message market (press KEY[0] after switching) |
| SW[7] | 0 = market view, 1 = level view |
| SW[6] | Level view side (0 BID, 1 ASK) |
| SW[5:0] | Level view price level |

Market view: `HEX5-4` best bid, `HEX3-2` best ask, `HEX1-0` message count ("--" = empty side).
Level view: `HEX5-4` the level, `HEX3-0` the quantity there.

LEDR[9] bids exist, LEDR[8] asks exist, LEDR[7] feed finished, LEDR[6] book busy,
LEDR[5] last message was a trade, LEDR[4] last side (on = ASK), LEDR[3:2] last type, LEDR[0] auto-play.

## Demo script for the TA (about 3 minutes)

What the HEX displays should show at each KEY[1] press with SW all down (test data):

| Press | Message | HEX (bid ask count) |
|---|---|---|
| 1 | ADD BID 100 @10 | `10 -- 01` |
| 2 | ADD BID 50 @12 | `12 -- 02` |
| 3 | ADD ASK 70 @15 | `12 15 03` |
| 4 | ADD ASK 30 @14 | `12 14 04` |
| 5 | ADD BID 25 @12 | `12 14 05` |
| 6 | CANCEL order 2 (12 still has 25) | `12 14 06` |
| 7 | TRADE 10 of order 4 @14 | `12 14 07` |
| 8 | TRADE 20 of order 4 (level 14 empty) | `12 15 08` |
| 9 | CANCEL order 5 (level 12 empty) | `10 15 09` |
| 10 | CANCEL unknown order 99 (ignored) | `10 15 10` |
| 11 | ADD BID 40 @13 | `13 15 11` |
| 12 | CANCEL order 6 | `10 15 12` |
| 13 | CANCEL order 1 (no bids left) | `-- 15 13` |
| 14 | END | LEDR[7] on |

Then: flip SW[7] up, set SW[6]=1 and SW[5:0]=15 → HEX shows `15 0070` (70 shares at ask 15).
Finally: SW[8] up, KEY[0], SW[9] up → the market data plays and bid/ask move around 26–33.
