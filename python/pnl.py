"""
Reference model of pnl_tracker.v (Pierce). One call = one clock edge.

  buy  (side 0): position += qty, cash -= px * qty
  sell (side 1): position -= qty, cash += px * qty
  mark = floor(mid) while both sides of the book exist, held otherwise
  pnl  = cash + position * mark, registered (uses the values from before this edge)
"""
from dataclasses import dataclass

BUY, SELL = 0, 1


@dataclass(frozen=True)
class PnlState:
    position: int = 0
    cash: int = 0
    mark: int = 0
    pnl: int = 0


def pnl_step(st, fill, top):
    """fill = (valid, side, px, qty); top = (best_bid, bid_valid, best_ask, ask_valid)."""
    valid, side, px, qty = fill
    best_bid, bid_valid, best_ask, ask_valid = top
    position, cash = st.position, st.cash
    if valid:
        signed_qty = qty if side == BUY else -qty
        position += signed_qty
        cash -= signed_qty * px
    mark = (best_bid + best_ask) >> 1 if bid_valid and ask_valid else st.mark
    return PnlState(position, cash, mark, st.cash + st.position * st.mark)
