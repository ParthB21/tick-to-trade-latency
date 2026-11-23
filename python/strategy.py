"""
Reference model of strategy.v (Pierce). Market making v2: quote a fixed
half-spread around the mid, both sides shifted against our inventory.

Prices are levels 0..63. mid2 = best_bid + best_ask is the mid in half-ticks,
so no fractions are needed: floor(mid) = mid2 >> 1, ceil(mid) = (mid2 + 1) >> 1.
"""
from msgfmt import N_LEVELS

MAX_PX = N_LEVELS - 1
SKEW_SHIFT = 3


def clamp_px(px):
    return max(0, min(MAX_PX, px))


def skew_ticks(position, skew_k):
    """position * skew_k / 8, rounded toward zero so long and short skew symmetrically."""
    ticks = (abs(position) * skew_k) >> SKEW_SHIFT
    return -ticks if position < 0 else ticks


def strategy(best_bid, bid_valid, best_ask, ask_valid, half_spread, size, position, skew_k):
    """Returns (ok, bid_px, ask_px, size). Prices are don't-care when ok is False."""
    ok = bid_valid and ask_valid and best_bid < best_ask
    mid2 = best_bid + best_ask
    skew = skew_ticks(position, skew_k)
    # skew stops at the best non-crossing price so the reducing side stays live
    bid = clamp_px(min((mid2 >> 1) - half_spread - skew, best_ask - 1))
    ask = clamp_px(max(((mid2 + 1) >> 1) + half_spread - skew, best_bid + 1))
    return ok, bid, ask, size
