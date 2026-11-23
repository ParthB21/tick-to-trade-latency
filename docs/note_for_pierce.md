# Note for Pierce: what changed when your M2 branch was merged with mine

`feat/m2-trading` is merged into `feat/m2-market`. Your strategy, risk gate, P&L tracker, dashboard and their testbenches are unchanged. Everything passes after the merge (`sim\run_m2_checks.ps1`).

## What I changed in your files, and why

| File | Change | Why |
|---|---|---|
| `rtl/hft_top.v` | Your placeholder fill wires (tied to 0) are now driven by `matching_engine` (`u_match`). | Connects fills to `pnl_tracker`. |
| `tb/hft_top_tb.v` | `FRAMES_TO_WAIT` 2 → 3. | See "The frame-dump bug" below. |
| `python/e2e.py` | Adds `MatchingEngine` to the chain, with the hardware's timing (below). The expected frame uses the settled P&L (`cash + position * mark`). | With real fills, position is no longer 0. |
| `sim/run_hft_top.do`, `sim/run_all.sh` | Added my files to the `hft_top` file list. | So the scripts still compile. |

**Name clash:** we both wrote a module called `bin2bcd`. I kept yours (sequential, used by the dashboard) as `rtl/bin2bcd.v` and renamed mine (combinational, used by the HEX views) to `rtl/bin2bcd_comb.v`.

I took your `python/pnl.py` and `python/strategy.py` unchanged. My placeholder P&L model is gone.

## Timing inside one message (the models now match this)

| Cycle | What happens |
|---|---|
| d | The order book's `done`. Your strategy snapshots best bid/ask **and `position`**, which is the position *before* this message's fill. |
| d+1 | `fill_valid` (matching engine). |
| d+2 | `pnl_tracker` has the new position. The risk gate samples it while `quote_valid` is high, so the limits use the position *after* the fill. |
| d+3 | `order_valid`. The matching engine reloads its remaining size. |

So the skew lags one message behind, and the risk limits do not lag. Both `e2e.py` and `system_model.py` model this. All 1000 orders and every system-test row match the hardware.

## The frame-dump bug

`hft_top_tb` counts a frame when the ladder ends (row 191). Your dashboard draws the position/P&L text below that, using values latched at the frame's start. With 2 frames, the dumped text was latched before the feed ended (+000 / +00000), while the model expected the final values (+001 / +00056). It passed on your branch only because position was always 0 there. With 3 frames it passes: 76,800/76,800 pixels.

## Results after the merge (half-spread 1, size 2, max position 8, plus the keyboard script)

| SW[2] skew | Fills | Final position | Cash | P&L |
|---|---|---|---|---|
| off | 34 | +5 | -97 | +28 |
| on (SKEW_K = 2) | 42 | +1 | +25 | +50 |

Your e2e at full speed with skew on: 1000/1000 orders, 0 pixel mismatches, final position +1, P&L +56.
