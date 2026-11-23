# Milestone 2: market side (Parth)

New in M2: matching engine, PS/2 order entry (receiver, scan-code decoder, entry FSM),
order arbiter, a per-block Python reference model for each block chained into one system
model, and a system testbench that checks `hft_top` against that model on every message.
The order book design is unchanged except that order IDs are now 11 bits, adding a source bit.

Figures are in `docs/figures/` (regenerate with `python docs/figures/make_m2_figures.py`).
They use Humor Sans if it's installed, as in M1, and Comic Sans otherwise.

## Results at a glance

| Check | Result |
|---|---|
| Order book alone (`order_book_tb`) | 27/27 (the 23 M1 checks plus 4 for the source bit) |
| Feed + book, 1000 messages vs `ref_model.py` | 1000/1000, 8.46 cycles/message average (testbench prints 8: integer division) |
| Matching engine (`matching_engine_tb`) | 13/13 named cases, 500/500 random vectors vs `matching.py` |
| Order arbiter (`order_arbiter_tb`) | 6/6: same-cycle, keyboard while busy, back-to-back, 360-message stress; 371 sent = 371 received, 0 misrouted `done` |
| Keyboard path (`order_entry_tb`) | 10/10: 12/12 messages vs `order_entry.py`, 9/9 rejects, bad-parity frame dropped, 7 display checks |
| Pierce's e2e (`hft_top_tb` + `e2e.py`) | 1000/1000 orders, 76,800/76,800 pixels, tick-to-trade still 7 to 8 cycles |
| System (`hft_system_tb` vs `system_model.py`), half-spread 1 | 1010/1010 messages (1000 ROM + 10 keyboard), 39 fills, 3 keyboard rejects |
| System, half-spread 0 | 1010/1010, 203 fills |
| Board demo sequence (13-message test + keyboard) | 17/17 messages, 3 fills |
| Quartus (`hft_top`) | 0 errors, Fmax 84.25 MHz, setup slack +8.13 ns, hold slack +0.17 ns, 1,006 ALMs (3%), 311,168 block-memory bits (8%) |

Run all of them: `cd sim` then `.\run_m2_checks.ps1`.

Mutation checks:
- A copy of the matching engine with `>` instead of `>=` fails 5 named cases and 46 vectors.
- A copy of the arbiter with feed priority instead of keyboard priority fails 5 of 6 checks.

So the tests do catch those bugs.

---

## 1. Order book: how best bid / best ask are found (answer to the TA's question)

**Summary.** We never scan the 64 price levels. Best bid and best ask come out in the same cycle a level changes, from two 64-bit registers and two priority encoders.

**How it works** (Figure 1, `book_datapath.png`):

- The **level RAM** (128 x 13, address `{side, price}`) stores only the total quantity at each level. It's never searched.
- Two **64-bit mask registers**, `bid_mask` and `ask_mask`, have bit *p* = 1 when level *p* has any quantity. In the `LVL_UPD` state, the new quantity for the level being changed is compared with 0 and the result is written into that one mask bit. That's 1 comparator and 1 flip-flop write per message.
- Two **priority encoders** (`prio_enc64.v`) read the masks:
  - highest set bit of `bid_mask` → `best_bid`
  - lowest set bit of `ask_mask` → `best_ask`
  - `valid` = any bit set (that side isn't empty)
- They're purely combinational, so `best_bid`/`best_ask` are already correct in the `DONE` cycle.
- The order table RAM (now 2048 x 21) is only used by CANCEL/TRADE to look up an order's side, price and remaining quantity.
- `lvl_view` and `lvl_view2` are identical copies of the level RAM. They give the VGA dashboard and the HEX depth views their own read ports, so displaying never stalls the book.

**Change for M2:** the order ID is `{source, id}`, so keyboard order 5 and ROM order 5 are different orders. The order table doubled to 2048 entries and the RAM clear after reset now takes 2048 cycles (41 µs). The first message after reset now takes 2052 cycles instead of 1028. Nothing else changed.

**Simulation figure:** `do run_order_book.do`, zoom 41,000–42,800 ns. Show `bid_mask`/`ask_mask` (hex) changing in `LVL_UPD`, and `best_bid`/`best_ask` changing on the same clock edge.

> **Figure 1.** Order book datapath. The masks and priority encoders give best bid/ask in one cycle. The level RAM holds quantities only.

---

## 2. Matching engine (`rtl/matching_engine.v`)

**Summary.** A simulated exchange. It decides when the replayed market would have traded with our own resting quotes, and outputs fills for Pierce's P&L tracker.

**How it works** (Figure 2, `matching_datapath.png`):

- The book's trade event says "the resting order on side S at price p traded qty Q". `trade_side` is the side of the resting order that was hit.
- **Bid side at p:** someone sold down to p. Our bid fills if it's live and `our_bid_px >= p`.
- **Ask side at p:** our ask fills if it's live and `our_ask_px <= p`.
- This is the "at or through" rule:

  | Half-spread | Trades in 1000 messages | Fills |
  |---|---|---|
  | 0 | 202 | 202 |
  | 1 | 202 | 38 |

- Fill price = our price. Fill qty = `min(trade_qty, remaining)`.
- `bid_rem`/`ask_rem` are reloaded from `our_size` on every `order_valid`, so one quote can never fill more than its size.
- **Timing:** `trade_valid` comes with the book's `done` (cycle d), and `fill_valid` follows in d+1. The risk gate's next `order_valid` comes at d+3, so a fill is always checked against the quote that was resting *before* the message, as on a real exchange.
- Our fills don't change the replayed book (no market impact). This is the usual assumption when replaying recorded data.
- Datapath only: 2 comparators, 2 min-selects, 2 subtractors and registers. No FSM.

**Signals in the waveform** (`do run_matching_engine.do`, zoom 40–840 ns):

| Signal | Meaning |
|---|---|
| `order_valid` | the risk gate just sent a quote; `bid_rem`/`ask_rem` reload to `our_size` |
| `our_bid_px` / `our_ask_px`, `*_live` | our resting quote |
| `trade_valid`, `trade_side`, `trade_price`, `trade_qty` | the book's trade event |
| `bid_hit` / `ask_hit` | the comparator result in the same cycle |
| `fill_valid`, `fill_side`, `fill_px`, `fill_qty` | the fill, one cycle later |
| `bid_rem` / `ask_rem` | shares left on the quote |

> **Figure 2.** Matching engine datapath.
>
> **Figure 3** (waveform, 60–400 ns): bid 30 x 4.
> - A trade at 30 fills 4.
> - The same quote can't fill again (rem 0).
> - After a requote, a trade at 31 is behind us (no fill), and a trade at 28 is through us (fill at *our* 30).

---

## 3. Order arbiter (`rtl/order_arbiter.v`)

**Summary.** Merges the ROM feed and keyboard orders into the order book's single input, one message at a time, with nothing lost or duplicated.

**Collision policy** (the TA asked for this to be defined):

1. A source is granted only when the arbiter is IDLE and the book is ready.
2. If both request in the same cycle, the **keyboard wins** (fixed priority). Keyboard messages come from a person typing, so the feed can't be starved.
3. **The ROM message isn't lost.** The feed handler stays in SEND with `msg_valid` high and its message register unchanged until `f_ready`.
4. **The keyboard message isn't lost.** Order entry holds `k_valid` and `k_msg` until `k_ready`, and ignores keys until then, so it can't submit a second message.
5. `done` is routed back only to the source that owns the message in the book, so the feed handler's WAIT state never sees a keyboard message finish.
6. The source bit becomes order-ID bit 10.

**State table** (Figure 4, `arbiter_fsm.png`):

| State | Outputs | Next |
|---|---|---|
| IDLE (0) | `b_valid = k_valid \| f_valid`; message mux = keyboard if `k_valid` else feed; `k_ready = book_ready & k_valid`; `f_ready = book_ready & f_valid & !k_valid` | KBD if keyboard granted, FEED if feed granted |
| FEED (1) | `owner = 0`; `f_done = b_done` | IDLE on `b_done` |
| KBD (2) | `owner = 1`; `k_done = b_done` | IDLE on `b_done` |

The arbiter adds **no latency**: in IDLE the mux and handshake are combinational. Tick-to-trade is still 7 to 8 cycles.

**Testbench** (`order_arbiter_tb.v`). The feed, keyboard and book are stand-ins with the real handshakes and timing (book: 5 cycles between accepts for an ADD). Each message carries a unique tag in its ID field, and the book stand-in logs every message it accepts.

**Annotated waveform** (`do run_order_arbiter.do`):

| Case | Zoom | Events | Shows |
|---|---|---|---|
| 1, same cycle | 80–360 ns | `f_valid` and `k_valid` both rise at 90 ns. Book accepts KBD 700 at 110 ns. `f_valid` stays high (feed held in SEND) until the book accepts FEED 2 at 210 ns. | keyboard priority; feed message held, not lost |
| 2, keyboard while busy | 420–800 ns | Book accepts FEED 4 at 450 ns. `k_valid` rises while the book is busy, and `k_ready` stays low until KBD 702 is accepted at 550 ns. FEED 6 at 650 ns. | keyboard waits for the book, goes next |
| 3, back-to-back | 860–1480 ns | FEED 8 at 890 ns, KBD 704 at 990, FEED 10 at 1090. Then KBD 706 and FEED 12 request in the same cycle: KBD 706 at 1190, FEED 12 at 1290, FEED 14 at 1390. | feed back-to-back with keyboard messages inserted; `f_done` only for feed, `k_done` only for keyboard |
| 4, stress | 1550 ns – end | 300 feed messages with random gaps and 60 keyboard messages at random times | none lost or repeated, in order per source (checked by counting tags) |

What to label on the screenshot:
- `arb_state_name` (IDLE/FEED/KBD)
- `owner`
- `f_valid` held high while waiting
- `k_ready`/`f_ready` pulses on grant
- `b_id` (hex; bit 10 set = keyboard)
- `f_done`/`k_done` going to only one side

> **Figure 4.** Arbiter FSM.
>
> **Figures 5–7.** Cases 1, 2 and 3 waveforms, with the zoom ranges above.

---

## 4. Keyboard order entry (`ps2_rx.v`, `kb_decoder.v`, `order_entry.v`)

**Summary.** You type orders on a PS/2 keyboard. They become 32-bit messages in exactly the ROM format and go through the arbiter into the book, so the bot reacts to them like any other market order.

**Key grammar:**

| Typed | Message | Notes |
|---|---|---|
| `B <price> Space <qty> Enter` | ADD bid | gets the next keyboard ID (1, 2, ...) |
| `S <price> Space <qty> Enter` (or `A`) | ADD ask | |
| `X <id> Enter` (or `C`) | CANCEL that keyboard order | |
| `T <id> Space <qty> Enter` | TRADE against that keyboard order | lets you cause a fill on demand |
| `Esc` / `Backspace` | clear / delete last digit | |

Rejected, showing `Err` and sending nothing:
- price > 63
- qty 0 or > 8191
- id 0 or > 1023
- an ADD that would cross the book (bid ≥ best ask, or ask ≤ best bid)

**How it works:**

- **`ps2_rx`** (receive only; we never send commands to the keyboard):
  - `PS2_CLK` and `PS2_DAT` go through 2-flop synchronisers. A third flop finds the falling edge of the PS/2 clock.
  - 11 bits are shifted in: start, 8 data (LSB first), odd parity, stop.
  - After the 11th bit it checks start = 0, stop = 1 and odd parity. A good frame pulses `rx_valid`; a bad one pulses `frame_err` and is dropped.
  - A 1 ms timeout with no clock edge resets the bit counter, so a half-received frame can't shift every later byte.
  - **This is our own receiver**, written instead of the course PS/2 core (the proposal said we'd use the course core). That means less cited code.
- **`kb_decoder`:**
  - `F0` means the next byte is a key release, so it's ignored.
  - `E0` means an extended key; only keypad Enter is used.
  - Any other byte is a key press and is looked up in a case table: digits on the top row or keypad, and B S A X C T Space Enter Esc Backspace.
- **`order_entry`:**
  - Digits are stored as typed, as 4 BCD digits, which makes the display trivial.
  - They're converted to binary with shifts and adds, with no divider:
    - x10 = x<<3 + x<<1
    - x100 = x<<6 + x<<5 + x<<2
    - x1000 = x<<10 − x<<4 − x<<3

**State table** (Figure 8, `entry_fsm.png`):

| State | What it does | Next |
|---|---|---|
| CMD (0) | waits for a command letter | B/S/X/T → NUM1 |
| NUM1 (1) | digits → price (B/S) or id (X/T) | Space (B/S/T) → NUM2; Enter on X with a good id → SEND; bad id → CMD + Err |
| NUM2 (2) | digits → qty | Enter, checks pass → SEND; checks fail → CMD + Err |
| SEND (3) | `k_valid = 1`, keys ignored | `k_ready` → CMD, shows the order ID |

A letter in CMD/NUM1/NUM2 starts a new command. Esc always goes back to CMD.

**HEX entry view** (KEY[2], or press any key):

| Situation | Shows |
|---|---|
| idle | `------` |
| typing | `b P _ _ 1 2` (P = price, q = qty, d = id) |
| sent | `b d 0001` (order ID 1) |
| rejected | `E r r` |

**Simulation** (`do run_order_entry.do`). The testbench drives real PS/2 frames (2 µs clock half-period instead of a real keyboard's 30–50 µs, to keep simulation short; the receiver only looks for edges).

Zoom 0–960 µs for the first line, `B12 50 Enter` (18 bytes):
- `ps2_clk`/`ps2_dat` frames
- `rx_valid` with `rx_byte` 32, F0, 32 (B pressed and released)
- `key_valid` with `key_code`
- `entry_state_name` going CMD → NUM1 → NUM2 → SEND
- `k_msg` = `06002032` = ADD bid, price 12, id 1, qty 50
- the arbiter stand-in raising `k_ready` 6 cycles later

> **Figure 8.** Order entry FSM.
>
> **Figure 9.** One PS/2 frame decoded.
>
> **Figure 10.** `B12 50 Enter` becoming one message.

---

## 5. Reference models (TA feedback 1)

One Python model per block, each with the same interface as its Verilog, plus the chain:

| Block | Model | Checked by |
|---|---|---|
| order book | `ref_model.py` (source bit added) | `order_book_tb`, `feed_book_tb` + `compare.py` |
| strategy (Pierce) | `strategy.py` (now with optional `position`, `skew_k`; default 0 = M1) | `strategy_tb` |
| risk gate (Pierce) | `risk.py` | `risk_gate_tb` |
| matching engine | `matching.py` | `matching_engine_tb` (`gen_match_vectors.py`) |
| keyboard decode + entry | `order_entry.py` | `order_entry_tb` (`gen_entry_vectors.py`) |
| P&L (Pierce) | `pnl.py`: **placeholder** until Pierce's tracker exists | — |
| **whole system** | `system_model.py` chains all of the above | `hft_system_tb` + `sys_compare.py` |

**`system_model.py`** replays the ROM plus a keyboard script (`sim/kb_script.txt`: `<after_n> <keys>`). For every message the book processes, it writes:
- best bid/ask
- our quotes after the risk gate
- the fill (if any)
- position and cash

**`hft_system_tb.v`** steps the real `hft_top` with KEY[1] and types the same script as real PS/2 frames on the `PS2_CLK`/`PS2_DAT` pins. It logs the same columns from `hft_top`'s internal signals (`book_done`, `arb_owner`, `fill_*`, `order_valid`, `our_*`). `sys_compare.py` compares them column by column.

Position/cash show `na` until Pierce's P&L tracker is in `hft_top`. Define `HAS_PNL` in the testbench then.

The keyboard script covers:
- adds, cancels, a keyboard trade that fills our ask
- a crossing add, a bad price, qty 0
- Backspace, Esc
- an unknown-ID cancel, a trade on a deleted ID
- an order typed after the END word

---

## 6. hft_top changes (integration)

- **PS/2 pins.** `PS2_CLK`/`PS2_DAT` added as inputs (pins AD7/AE7 are already in the `.qsf`).
- **Arbiter in the path.** It sits between the feed handler and the book. The feed handler's `book_ready`/`book_done` are now `f_ready`/`f_done`.
- **New HEX views.** KEY[2] cycles bot → market → bid depth → ask depth → **entry** → **fills** → bot. A keyboard key jumps straight to the entry view.

  Fills view:

  | Digit | Shows |
  |---|---|
  | HEX5 | `b` (we bought) or `S` (we sold), last fill |
  | HEX4–3 | its price |
  | HEX2–0 | number of fills |
  | before any fill | `F-----` |

- **No `/` or `%`.** HEX digits now go through `bin2bcd.v` (shift-and-add-3). `seg7.v` is 5 bits wide, with letters.
- **`position` still tied to 0.** It waits for Pierce's P&L tracker (see `docs/note_for_pierce.md`).

## 7. Files (new or changed in M2)

| File | What it is |
|---|---|
| `rtl/matching_engine.v` | new: simulated exchange, fills |
| `rtl/order_arbiter.v` | new: feed + keyboard → book |
| `rtl/ps2_rx.v` | new: PS/2 receiver (our own) |
| `rtl/kb_decoder.v` | new: scan codes → keys |
| `rtl/order_entry.v` | new: keys → 32-bit messages, entry display |
| `rtl/bin2bcd.v` | new: binary → BCD for the HEX displays |
| `rtl/order_book.v` | changed: 11-bit ID (source bit), 2048-entry order table |
| `rtl/seg7.v` | changed: 5-bit input, letters |
| `rtl/hft_top.v` | changed: integration, new views |
| `rtl/milestone1_top.v` | changed: pads the ID and `seg7` inputs (still compiles) |
| `tb/matching_engine_tb.v`, `tb/order_arbiter_tb.v`, `tb/order_entry_tb.v`, `tb/hft_system_tb.v` | new testbenches |
| `tb/order_book_tb.v`, `tb/feed_book_tb.v`, `tb/hft_top_tb.v`, `tb/mocks/vga_adapter.v` | updated for the changes above |
| `python/matching.py`, `order_entry.py`, `pnl.py`, `system_model.py`, `sys_compare.py`, `gen_match_vectors.py`, `gen_entry_vectors.py`, `demo_table.py` | new models and tools (testing only) |
| `python/strategy.py`, `python/ref_model.py` | optional skew / source bit added |
| `sim/run_matching_engine.do`, `run_order_arbiter.do`, `run_order_entry.do`, `run_system.do`, `run_m2_checks.ps1` | new scripts |
| `sim/kb_script.txt`, `sim/kb_demo_small.txt` | keyboard scripts (system test, board demo) |
| `docs/figures/*.png`, `docs/figures/make_m2_figures.py` | M2 figures |
| `docs/note_for_pierce.md` | fill interface + skew bring-up note |

## 8. Corrections to the M1 write-up

- The order book has **4** memories: the order table, the level RAM, and two level copies for the two read ports.
- Throughput: **average 8.46 cycles per message** (≈169 ns). The testbench prints 8 because of integer division.

## 9. Next (week 12)

- Latency counter on the HEX displays (`msg_start` → `order_valid`; currently 7 to 8 cycles).
- Connect fills to Pierce's P&L tracker and close the position → risk loop, with skew off first.
- An end-to-end run with `--feedback`.
