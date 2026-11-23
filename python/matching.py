"""
Reference model of matching_engine.v (Parth, M2): the simulated exchange.

It holds our resting quotes (from the risk gate) and watches the order book's
trade events. Rule ("at or through"): a trade against the resting BID side at
price p fills our bid if it is live and our_bid_px >= p (we are at least as
good as the order that traded, so the seller would have hit us). Mirror rule
for the ASK side. Fill price = our price, fill qty = min(trade qty, what is
left of our quote). Our fills do not change the replayed book (no market impact).

Same interface as the Verilog, one method per input pulse:
  on_trade(side, price, qty) -> fill or None     (book trade_valid)
  on_order(bid_live, bid_px, ask_live, ask_px, size)  (risk gate order_valid)
If both pulse in the same cycle, the hardware checks the fill against the OLD
quote and then loads the new one, so call on_trade first, then on_order.
"""
from collections import namedtuple
from msgfmt import BID

Fill = namedtuple("Fill", "side px qty")     # side 0 = we bought, 1 = we sold


class MatchingEngine:
    def __init__(self):
        self.bid_px = self.ask_px = 0
        self.bid_rem = self.ask_rem = 0
        self.fills = 0

    def on_order(self, bid_live, bid_px, ask_live, ask_px, size):
        self.bid_px, self.ask_px = bid_px, ask_px
        self.bid_rem = size if bid_live else 0
        self.ask_rem = size if ask_live else 0

    def on_trade(self, side, price, qty):
        if side == BID and self.bid_rem and self.bid_px >= price:
            q = min(qty, self.bid_rem)
            self.bid_rem -= q
            self.fills += 1
            return Fill(0, self.bid_px, q)
        if side != BID and self.ask_rem and self.ask_px <= price:
            q = min(qty, self.ask_rem)
            self.ask_rem -= q
            self.fills += 1
            return Fill(1, self.ask_px, q)
        return None
