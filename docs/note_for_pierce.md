# Note for Pierce: fills, position and inventory skew (M2)

Hi Pierce. The matching engine is in `hft_top` now and produces fills. Here's what you need to know to hook up the P&L tracker, plus a suggestion for bringing up the skew safely. **I haven't changed `strategy.v` or `risk_gate.v`.**

## 1. Fill interface (from `rtl/matching_engine.v`, instance `u_match` in `hft_top`)

| Signal | Width | Meaning |
|---|---|---|
| `fill_valid` | 1 | 1-cycle pulse, one cycle after the order book's `done` |
| `fill_side` | 1 | 0 = we bought (our bid was hit), 1 = we sold (our ask was lifted) |
| `fill_px` | 6 | our price (0..63) |
| `fill_qty` | 8 | shares, at most `our_size` |
| `fill_count` | 16 | fills since reset (HEX fills view) |

Rule: a trade at or through our resting price fills us at our own price. Size is reloaded on every `order_valid`, so a single quote never fills more than its size.

## 2. Where `position` goes

`hft_top.v` still has `wire signed [9:0] position = 10'sd0;`. Replace that line with your tracker's output. The risk gate already takes `position`.

**Timing:** `done` is cycle d. `fill_valid` is high in d+1. If your tracker registers the position at the end of d+1, it's valid in d+2. That's exactly the cycle the risk gate samples (`quote_valid` is high in d+2). So the risk check for a message uses the position *after* that message's fill, which is also what the Python model does (`python/system_model.py --feedback`). If your tracker needs an extra cycle, the risk gate sees the position from one message earlier. That's fine too, but tell me and I'll make the model match.

## 3. Suggested bring-up: skew off first, then on

1. Add the skew as a parameter or switch (e.g. `SKEW_K`) and set it to 0 first. Close the fill → position → risk loop with no skew. The strategy is then exactly M1, so any mismatch is in the P&L/position path, not the strategy.
   - Check: `python ../python/system_model.py ../mem/market_data.hex kb_script.txt sys_expected.txt --feedback --skew-k 0`
     against `tb/hft_system_tb.v` (define `HAS_PNL` and point the `$fdisplay` at your `position` and `cash` signals). Then run `python ../python/sys_compare.py sys_expected.txt sys_out.txt`.
2. Then turn the skew on and run the same comparison with `--skew-k <K>`.

`python/strategy.py` now takes optional `position` and `skew_k` arguments (default 0, so your M1 vectors and `e2e.py` give identical results). The formula I used is only a proposal. If yours differs, change `skew_ticks()` to match your hardware:

```
skew   = (position * skew_k) >>> 3        // arithmetic shift; floor for negative positions
bid_px = clamp(floor(mid) - half_spread - skew)
ask_px = clamp(ceil(mid)  + half_spread - skew)   // long -> both quotes move down
```

What the model shows on the 1000-message data plus the keyboard script (half-spread 1, size 2, max position 8):

| Setting | Fills | Final position | Cash (ticks x shares) |
|---|---|---|---|
| no position feedback (hardware today) | 39 | +15 | -403 |
| feedback, skew 0 | 34 | +5 | -97 |
| feedback, skew_k 4 | 42 | 0 | +46 |

## 4. P&L model

`python/pnl.py` is a placeholder I wrote so the system model has position and cash columns. It's your block: make it match `pnl_tracker.v` exactly (widths, saturation, when it updates) and keep the interface: `on_fill(side, px, qty)`, `position`, `cash`.

## 5. Two other things

- `seg7.v` is now 5 bits wide (letters for the new views). In ModelSim a 4-bit connection leaves the top bit as `z` (blank digit), so pad it: `.d({1'b0, x})`. I've already done this in `hft_top_tb.v`.
- `tb/mocks/vga_adapter.v` now uses the newer adapter's ports (`COLOR_DEPTH`, `.color`, `.write`), so `hft_top_tb` runs again. Your e2e still passes: 1000/1000 orders, 76,800/76,800 pixels.
