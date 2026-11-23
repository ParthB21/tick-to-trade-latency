"""
Reference model of the P&L tracker (Pierce's block, M2).

PLACEHOLDER written by Parth so the system model has position and cash columns.
Pierce owns this block: when pnl_tracker.v exists, change this file to match it
exactly (widths, saturation, when position updates) and keep the interface:
  on_fill(side, px, qty)   side 0 = we bought, 1 = we sold
  position                 shares, + = long
  cash                     price ticks x shares, starts at 0
  mark(mid2)               mark-to-market P&L in half-ticks: 2*cash + position*mid2
"""


class Pnl:
    def __init__(self):
        self.position = 0
        self.cash = 0

    def on_fill(self, side, px, qty):
        if side == 0:
            self.position += qty
            self.cash -= px * qty
        else:
            self.position -= qty
            self.cash += px * qty

    def mark(self, mid2):
        return 2 * self.cash + self.position * mid2
