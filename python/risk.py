"""
Reference model of risk_gate.v (Pierce). One call = one clock edge.

Reject flag bits (sticky until reset):
  0 kill   1 quote not ok   2 size > max_size   3 long limit   4 short limit   5 crossing
"""
from dataclasses import dataclass, replace

KILL, NOT_OK, SIZE, LONG, SHORT, CROSS = (1 << b for b in range(6))


@dataclass(frozen=True)
class RiskState:
    order_valid: bool = False
    bid_live: bool = False
    bid_px: int = 0
    ask_live: bool = False
    ask_px: int = 0
    size: int = 0
    killed: bool = False
    reject: int = 0


def risk_step(st, kill_sw, quote, top, position, max_pos, max_size):
    """quote = (valid, ok, bid_px, ask_px, size); top = (best_bid, bid_valid, best_ask, ask_valid)."""
    valid, ok, bid_px, ask_px, size = quote
    best_bid, bid_valid, best_ask, ask_valid = top
    st = replace(st, order_valid=False)

    if kill_sw and not st.killed:
        return replace(st, order_valid=True, killed=True, bid_live=False, ask_live=False,
                       reject=st.reject | KILL)
    if not valid:
        return st

    size_bad = size > max_size
    long_bad = position + size > max_pos
    short_bad = position - size < -max_pos
    bid_cross = ask_valid and bid_px >= best_ask
    ask_cross = bid_valid and ask_px <= best_bid
    common = not st.killed and ok and not size_bad
    bid_ok = common and not long_bad and not bid_cross
    ask_ok = common and not short_bad and not ask_cross

    flags = ((KILL if st.killed else 0) | (0 if ok else NOT_OK) | (SIZE if size_bad else 0)
             | (LONG if long_bad else 0) | (SHORT if short_bad else 0)
             | (CROSS if bid_cross or ask_cross else 0))
    return replace(st, order_valid=True, bid_live=bid_ok, bid_px=bid_px, ask_live=ask_ok,
                   ask_px=ask_px, size=size, reject=st.reject | flags)
