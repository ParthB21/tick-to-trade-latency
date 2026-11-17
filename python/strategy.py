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


def strategy(best_bid, bid_valid, best_ask, ask_valid, half_spread, size):
    """Returns (ok, bid_px, ask_px, size). Prices are don't-care when ok is False."""
    ok = bid_valid and ask_valid and best_bid < best_ask
    mid2 = best_bid + best_ask
    bid = clamp_px((mid2 >> 1) - half_spread)
    ask = clamp_px(((mid2 + 1) >> 1) + half_spread)
    return ok, bid, ask, size
