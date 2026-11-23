"""
Reference model of strategy.v (Pierce). Market making v1: quote a fixed
half-spread around the mid, no inventory skew.

Prices are levels 0..63. mid2 = best_bid + best_ask is the mid in half-ticks,
so no fractions are needed: floor(mid) = mid2 >> 1, ceil(mid) = (mid2 + 1) >> 1.
"""
from msgfmt import N_LEVELS

MAX_PX = N_LEVELS - 1


def clamp_px(px):
    return max(0, min(MAX_PX, px))


SKEW_SHIFT = 3          # skew in ticks = (position * skew_k) >> SKEW_SHIFT


def skew_ticks(position, skew_k):
    """Inventory skew (v2, proposed for Pierce; see docs/note_for_pierce.md).
    Python >> on a negative number floors, the same as Verilog >>> on a signed value.
    skew_k = 0 turns the skew off, giving exactly v1."""
    return (position * skew_k) >> SKEW_SHIFT


def strategy(best_bid, bid_valid, best_ask, ask_valid, half_spread, size, position=0, skew_k=0):
    """Returns (ok, bid_px, ask_px, size). Prices are don't-care when ok is False.
    position/skew_k are optional: with skew_k = 0 (the default) this is the M1 strategy.
    Long (position > 0) -> skew > 0 -> both quotes move down, so we sell more easily."""
    ok = bid_valid and ask_valid and best_bid < best_ask
    mid2 = best_bid + best_ask
    sk = skew_ticks(position, skew_k)
    bid = clamp_px((mid2 >> 1) - half_spread - sk)
    ask = clamp_px(((mid2 + 1) >> 1) + half_spread - sk)
    return ok, bid, ask, size
