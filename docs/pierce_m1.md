# Milestone 1: trading side (Pierce)

ROM -> feed handler -> order book (Parth) -> strategy -> risk gate (Pierce), with the
live book and our quotes on VGA and risk status on the LEDs.

## Files

| File | What it is |
|---|---|
| `rtl/strategy.v` | Market-making strategy v1 (mid +/- half-spread, no skew) |
| `rtl/risk_gate.v` | Parallel risk checks, kill switch, resting quote registers |
| `rtl/dashboard.v` | VGA scanner FSM: depth ladder + our quote markers |
| `rtl/sync2.v` | 2-FF synchroniser for switches and keys |
| `rtl/hft_top.v` | Board top level for M1 |
| `tb/strategy_tb.v`, `tb/risk_gate_tb.v` | Vector testbenches against the Python models |
| `tb/hft_top_tb.v` | End-to-end: full replay, order log, latency, frame dump, HEX, kill |
| `tb/mocks/vga_adapter.v` | Simulation-only VGA stub that stores pixels. Never add it to Quartus. |
| `python/strategy.py`, `risk.py`, `dashboard.py` | Reference models (testing only) |
| `python/gen_vectors.py` | Writes `sim/vectors/*.hex` |
| `python/e2e.py` | Chained model: Parth's book model -> strategy -> risk -> frame, diffed against the sim |

## Running the tests

Locally (Icarus Verilog), everything in one go:

```
sim/run_pierce.sh
```

In ModelSim, from `sim/`: `do run_strategy.do`, `do run_risk_gate.do`, `do run_hft_top.do`,
then `python ../python/e2e.py ../mem/market_data.hex out`.

Current results:

- strategy: 212 vectors pass (200 random + 12 edge cases), 2-cycle latency checked on every vector
- risk gate: 244 cycles pass, all 6 reject flags exercised, kill latch and reset tested
- end to end: 1000/1000 orders match the Python chain, 76,800/76,800 frame pixels match
- tick-to-trade: 7 to 8 cycles (140 to 160 ns) from `msg_start` to `order_valid`

Each testbench was also run against a deliberately broken copy of the RTL (ceil vs floor in
the strategy, missing sign extension in the risk gate, bar off-by-one in the dashboard) and
failed, so the tests are known to catch those bugs.

## Latency breakdown (7 to 8 cycles)

| Stage | Cycles |
|---|---|
| Feed hands message to book, book applies it (Parth) | 4 (ADD) or 5 (CANCEL/TRADE) |
| `done` -> strategy snapshot -> CALC -> `quote_valid` | 2 |
| `quote_valid` -> risk checks registered -> `order_valid` | 1 |

The first message after reset takes 1028 cycles because the order book clears its RAMs (1024 cycles) first.

## strategy.v

How it works:

- Trigger is the order book's `done` pulse. Best bid/ask are already updated in that cycle.
- FSM `IDLE -> CALC -> OUT`. IDLE snapshots the inputs on the trigger. CALC registers the
  quote. OUT pulses `quote_valid`.
- `mid2 = bid + ask` keeps the mid in half-ticks, so there are no fractions.
  `bid = (mid2 >> 1) - hs` is floor(mid) minus hs, and `ask = ((mid2 + 1) >> 1) + hs` is ceil(mid) plus hs.
- Both use 9-bit signed intermediates and are clamped to 0..63.
- `quote_ok` = both sides present and `best_bid < best_ask`.

Likely TA questions:

1. *Why snapshot the inputs instead of using them live?* So the quote is computed from one
   consistent book state even if the book changes mid-calculation. The testbench scrambles the
   inputs right after the trigger to prove the FSM ignores them.
2. *Why 9-bit signed?* `floor(mid) - 3` can go below 0. In 6-bit unsigned, -2 wraps to 62
   and the clamp can't tell it from a real 62. Signed 9-bit keeps it negative so the clamp
   sends it to 0. The v2 inventory skew also subtracts a signed value, so it reuses this.
3. *Why an FSM when it could be one combinational cycle?* The proposal promised a control FSM,
   and v2 adds a multiplier stage (`position * K`) that slots into CALC. It costs 1 extra cycle.

Known behaviour: with half-spread 0 and an even `mid2` (for example 30/32), bid = ask = 31.
We quote both sides at the same price. Use half-spread >= 1 for the demo.

## risk_gate.v

How it works:

- All checks are combinational comparators on the `quote_valid` cycle. The results are
  registered, so `order_valid` comes 1 cycle later.
- Per side:
  - `bid_ok = !killed & ok & !size_bad & !(pos+size > max_pos) & !(bid >= best_ask)`
  - `ask_ok = !killed & ok & !size_bad & !(pos-size < -max_pos) & !(ask <= best_bid)`
  - A rejected side goes not-live, so a stale quote is never left resting.
- Kill: the first cycle `kill_sw` is high, `killed` latches, both sides drop, and `order_valid`
  pulses (the cancel). Only reset clears it.
- Reject flags on LEDR[5:0] are sticky: 0 kill, 1 not ok, 2 size, 3 long, 4 short, 5 cross.
- `order_valid` pulses for every evaluated quote, even if both sides are rejected, so the
  latency counter always gets a stop.

Likely TA questions:

1. *Why reject per side?* At the long limit we must not buy more, but selling reduces risk,
   so the ask stays live. Rejecting both sides would trap us at the limit.
2. *How do you avoid signed/unsigned bugs?* Position is 10-bit two's complement. It is
   sign-extended to 11 bits, size is zero-extended, and all compares are between signed
   11-bit values. 11 bits holds 511 + 255 without overflow, and the tests include positions
   of +511 and -512.
3. *The crossing check reads the live best bid/ask, 2 cycles after the strategy's snapshot.
   Could it be stale?* No. The book needs at least 8 cycles per message, and the next
   message can't change the masks until at least 6 cycles after our check.

In M1 `position` is tied to 0 (no fills until the matching engine and P&L tracker exist in M2),
so the long/short limits only fire in the unit test.

## dashboard.v

How it works:

- A scanner with no erase state. It repaints all 192 ladder rows forever, writing either bar
  colour or black, so old bars disappear automatically.
- Per level: `ADDR_BID -> ADDR_ASK -> LATCH_ASK -> DRAW` (3 rows x 320 px, the third row is a
  black gap). Frame = 64 x (3 + 960) = 61,632 cycles = 1.23 ms, about 800 redraws per second.
- Parth's query port gives one side per read with 1 cycle of latency. The bid address goes out
  in ADDR_BID and its qty is latched in ADDR_ASK while the ask address goes out. The ask qty is
  latched in LATCH_ASK.
- Bar length = `min(qty >> 5, 159)`, and at least 1 px if the level is non-empty. Quantities
  reach 8191 (median about 960), so 32 shares per pixel keeps most bars readable.
- Our live quotes get yellow markers at x = 8..15 (bid row) and x = 304..311 (ask row). They
  are latched once per frame so a frame never shows half-old markers.

Likely TA questions:

1. *Why not erase and redraw?* Erasing doubles the work and makes the screen flicker. Repainting
   every pixel each pass is simpler (no erase state) and always shows the current book within
   1.2 ms.
2. *How do `x`, `y` and `plot` stay consistent?* `x`/`y` are registers, `colour` is
   combinational from those registers, and `plot` is "state == DRAW". All of them are stable
   before the clock edge the adapter samples on.
3. *How did you verify it without a monitor?* The sim VGA stub stores every plotted pixel.
   `e2e.py` renders the expected frame from the Python book and diffs all 76,800 pixels. An
   off-by-one in the bar length shows up as 32 wrong pixels.

## hft_top.v: board controls

| Input | Use |
|---|---|
| KEY[0] | reset |
| KEY[1] | step one message (when SW[1:0] = 00) |
| SW[1:0] | 00 step, 01 auto 4 msgs/s, 1x full speed |
| SW[4:3] | quote size 1 / 2 / 4 / 8 |
| SW[6:5] | half-spread 0..3 ticks |
| SW[8:7] | max position 4 / 8 / 16 / 32 |
| SW[9] | kill switch |

| Output | Shows |
|---|---|
| HEX5-4 / HEX3-2 | our bid / ask price ("--" = not live) |
| LEDR[9] | killed |
| LEDR[8] | feed finished |
| LEDR[7] / LEDR[6] | ask / bid live |
| LEDR[5:0] | sticky reject flags |

All switches and keys pass through `sync2`. HEX digits come from a comparator chain, not `/` or `%`.

## Putting it on the board

1. Quartus project in `quartus/`, device 5CSEMA5F31C6, top-level entity `hft_top`.
2. Add every file in `rtl/` (not `tb/`). Add the course VGA files (`vga_adapter.v`,
   `vga_controller.v`, `vga_address_translator.v`, `vga_pll.v`) and `black.mif`.
3. Import the course `DE1_SoC.qsf` pin assignments.
4. **Check the course `vga_adapter` ports and parameters against `hft_top.v`** (`plot`,
   `VGA_BLANK_N`, `RESOLUTION`, `BACKGROUND_IMAGE`). They were written from the handout,
   not the actual file.
5. Compile, check TimeQuest slack at 50 MHz, program, press KEY[0].
6. Demo: SW[1:0] = 01, SW[6:5] = 01, SW[4:3] = 01. Bars move and yellow markers track the mid.
   Flip SW[9]: markers vanish, HEX shows `-- --`, LEDR[9] lights.

## Still to settle with Parth

- `order_valid` pulses even when both sides are rejected (latency counter stop). Does that suit the latency counter?
- `hft_top.v` duplicates his step/auto-play logic from `milestone1_top.v`. Decide which top
  is the real one going forward.
- His `milestone1_top.v` uses `/ 10` and `% 10` for the HEX digits, which the course rules disallow.
- TRADE `trade_side` is the resting order's side, not the aggressor. This matters for M2 fills.
