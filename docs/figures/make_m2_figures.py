"""
M2 figures in the same hand-drawn style as M1 (matplotlib xkcd mode, blue = Parth's blocks).
Uses Humor Sans if it is installed (as in M1), otherwise Comic Sans.

  python make_m2_figures.py          -> writes the PNGs next to this file
    book_datapath.png     order book: masks -> priority encoders -> best bid/ask (TA question)
    arbiter_fsm.png       order arbiter FSM + collision policy
    entry_fsm.png         order entry FSM (keyboard)
    matching_datapath.png matching engine compare/fill datapath
    m2_block.png          M2 system block diagram
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Circle

HERE = os.path.dirname(os.path.abspath(__file__))
BLUE, RED, GREY, INK = "#1f5fbf", "#c0392b", "#555555", "#222222"
plt.rcParams["font.family"] = ["Humor Sans", "Comic Sans MS", "DejaVu Sans"]


def box(ax, x, y, w, h, title, sub="", col=BLUE, fs=13):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.02,rounding_size=0.08",
                                fill=False, lw=2, ec=col))
    if sub:
        ax.text(x, y + h * 0.16, title, ha="center", va="center", fontsize=fs, color=INK, weight="bold")
        ax.text(x, y - h * 0.2, sub, ha="center", va="center", fontsize=fs - 4, color=GREY)
    else:
        ax.text(x, y, title, ha="center", va="center", fontsize=fs, color=INK, weight="bold")


def arrow(ax, x0, y0, x1, y1, label="", col=INK, dashed=False, lx=0.0, ly=0.12, fs=10, rad=0.0):
    ax.annotate("", xy=(x1, y1), xytext=(x0, y0),
                arrowprops=dict(arrowstyle="-|>", lw=1.6, color=col, ls="--" if dashed else "-",
                                connectionstyle=f"arc3,rad={rad}"))
    if label:
        ax.text((x0 + x1) / 2 + lx, (y0 + y1) / 2 + ly, label, ha="center", va="center", fontsize=fs, color=col)


def state(ax, x, y, name, sub="", r=0.55, col=BLUE):
    ax.add_patch(Circle((x, y), r, fill=False, lw=2, ec=col))
    ax.text(x, y + (0.1 if sub else 0), name, ha="center", va="center", fontsize=13, weight="bold", color=INK)
    if sub:
        ax.text(x, y - 0.22, sub, ha="center", va="center", fontsize=8.5, color=GREY)


def canvas(w, h):
    fig, ax = plt.subplots(figsize=(w, h))
    ax.set_xlim(0, w)
    ax.set_ylim(0, h)
    ax.axis("off")
    return fig, ax


def save(fig, name):
    fig.tight_layout()
    fig.savefig(os.path.join(HERE, name), dpi=200)
    plt.close(fig)
    print("wrote", name)


def book_datapath():
    fig, ax = canvas(12, 6.6)
    ax.text(6, 6.25, "Order book: how best bid / best ask are found (no scan of the 64 levels)",
            ha="center", fontsize=15, weight="bold")
    box(ax, 1.4, 4.2, 2.2, 1.2, "message", "type side price\nid qty")
    box(ax, 4.4, 4.9, 2.6, 1.1, "order table RAM", "2048 x 21  {valid side price qty}")
    box(ax, 4.4, 3.2, 2.6, 1.1, "level qty RAM", "128 x 13  qty at {side, price}")
    box(ax, 7.6, 3.2, 2.2, 1.1, "qty != 0 ?", "1 comparator")
    box(ax, 7.6, 5.0, 2.4, 0.9, "bid_mask[63:0]", "64 flip-flops")
    box(ax, 7.6, 1.4, 2.4, 0.9, "ask_mask[63:0]", "64 flip-flops")
    box(ax, 10.6, 5.0, 2.2, 1.0, "prio_enc64", "highest set bit")
    box(ax, 10.6, 1.4, 2.2, 1.0, "prio_enc64", "lowest set bit")
    arrow(ax, 2.5, 4.4, 3.1, 4.8, "CANCEL/TRADE:\nlook up side, price", ly=0.35, fs=9)
    arrow(ax, 2.5, 4.0, 3.1, 3.3, "ADD: side, price", ly=-0.3, fs=9)
    arrow(ax, 4.4, 4.35, 4.4, 3.75)
    arrow(ax, 5.7, 3.2, 6.5, 3.2, "new qty", ly=0.2, fs=9)
    arrow(ax, 7.6, 3.75, 7.6, 4.55, "set / clear\nbit [price]", lx=0.75, ly=0, fs=9)
    arrow(ax, 7.6, 2.65, 7.6, 1.85, "", fs=9)
    arrow(ax, 8.8, 5.0, 9.5, 5.0)
    arrow(ax, 8.8, 1.4, 9.5, 1.4)
    ax.text(11.75, 5.0, "best_bid\nbid_valid", fontsize=11, va="center", ha="left", weight="bold", color=BLUE)
    ax.text(11.75, 1.4, "best_ask\nask_valid", fontsize=11, va="center", ha="left", weight="bold", color=BLUE)
    arrow(ax, 4.4, 2.65, 4.4, 0.6, "copies lvl_view, lvl_view2:\nread ports for VGA and HEX depth",
          dashed=True, col=GREY, lx=0, ly=-0.75, fs=9)
    ax.text(10.6, 3.2, "combinational:\nready in the SAME cycle\nthe mask bit changes", ha="center", va="center",
            fontsize=10, color=RED)
    ax.text(1.4, 2.2, "RAM keeps only the\nquantity per level.\nThe masks say which\nlevels are non-empty.",
            ha="center", va="center", fontsize=10, color=GREY)
    save(fig, "book_datapath.png")


def arbiter_fsm():
    fig, ax = canvas(7.5, 9)
    ax.text(3.75, 8.6, "Order arbiter FSM", ha="center", fontsize=15, weight="bold")
    state(ax, 3.75, 6.6, "IDLE", "b_valid = k_valid | f_valid")
    state(ax, 1.6, 3.6, "KBD", "owner = 1")
    state(ax, 5.9, 3.6, "FEED", "owner = 0")
    arrow(ax, 3.3, 6.2, 1.9, 4.1)
    arrow(ax, 4.2, 6.2, 5.6, 4.1)
    ax.text(3.75, 5.05, "to KBD: k_valid & book ready\n(keyboard wins ties)", fontsize=9, ha="center")
    ax.text(3.75, 4.05, "to FEED: f_valid & !k_valid\n& book ready", fontsize=9, ha="center")
    arrow(ax, 1.95, 4.15, 3.25, 6.1, "", rad=-0.45)
    ax.text(0.9, 5.7, "b_done\n(k_done)", fontsize=9, ha="center")
    arrow(ax, 5.55, 4.15, 4.25, 6.1, "", rad=0.45)
    ax.text(6.6, 5.7, "b_done\n(f_done)", fontsize=9, ha="center")
    ax.text(3.75, 1.5, "Nothing is lost: a source that is not granted keeps valid high\n"
                       "(feed handler stays in SEND, order entry stays in SEND).\n"
                       "done goes only to the owner; source bit = order ID bit 10.",
            ha="center", va="center", fontsize=10, color=GREY)
    save(fig, "arbiter_fsm.png")


def entry_fsm():
    fig, ax = canvas(8, 11)
    ax.text(4, 10.6, "Order entry FSM (PS/2 keyboard)", ha="center", fontsize=15, weight="bold")
    state(ax, 4, 9.0, "CMD", "wait for B S X T")
    state(ax, 4, 6.6, "NUM1", "price (B/S) or id (X/T)")
    state(ax, 4, 4.2, "NUM2", "qty (B/S/T)")
    state(ax, 4, 1.8, "SEND", "k_valid = 1")
    arrow(ax, 4, 8.45, 4, 7.15, "B / S / X / T", lx=0.9, ly=0, fs=10)
    arrow(ax, 4, 6.05, 4, 4.75, "Space\n(B/S/T)", lx=0.7, ly=0, fs=10)
    arrow(ax, 4, 3.65, 4, 2.35, "Enter,\nchecks pass", lx=0.85, ly=0, fs=10)
    arrow(ax, 4.5, 6.3, 4.5, 2.1, "", rad=-0.6)
    ax.text(6.3, 4.2, "X: Enter,\nid ok", fontsize=10, ha="center")
    arrow(ax, 3.5, 1.55, 3.5, 9.25, "", rad=-0.75)
    ax.text(0.65, 5.4, "k_ready\n(accepted)\n-> shows\n\"b d 0007\"", fontsize=10, ha="center", color=BLUE)
    arrow(ax, 3.45, 4.3, 3.47, 8.75, "", rad=-0.3, dashed=True, col=RED)
    ax.text(2.45, 5.3, "Enter,\ncheck\nfails\n-> \"Err\"", fontsize=10, ha="center", color=RED)
    ax.text(6.6, 8.9, "digits: shift into BCD\nBackspace: shift out\nEsc: back to CMD",
            fontsize=9.5, ha="center", color=GREY)
    save(fig, "entry_fsm.png")


def matching_datapath():
    fig, ax = canvas(11, 6)
    ax.text(5.5, 5.65, "Matching engine (simulated exchange)", ha="center", fontsize=15, weight="bold")
    box(ax, 1.5, 4.2, 2.4, 1.1, "trade event", "side, price p, qty\n(from order book)", col=GREY)
    box(ax, 1.5, 1.8, 2.4, 1.1, "our quotes", "bid/ask px, live,\nsize (risk gate)", col=GREY)
    box(ax, 4.6, 4.2, 2.6, 1.1, "bid: px >= p ?", "ask: px <= p ?")
    box(ax, 4.6, 1.8, 2.6, 1.1, "bid_rem / ask_rem", "reload on order_valid")
    box(ax, 7.6, 3.0, 2.2, 1.1, "min(qty, rem)", "fill qty")
    box(ax, 10.0, 3.0, 1.6, 1.4, "fill regs", "valid side\npx qty")
    arrow(ax, 2.7, 4.2, 3.3, 4.2)
    arrow(ax, 2.7, 1.8, 3.3, 1.8)
    arrow(ax, 2.7, 2.1, 3.4, 3.8, "our px", fs=9, lx=-0.3)
    arrow(ax, 4.6, 2.35, 4.6, 3.65, "rem != 0", lx=0.55, ly=0, fs=9)
    arrow(ax, 5.9, 4.0, 6.5, 3.3, "hit", fs=9, ly=0.25)
    arrow(ax, 5.9, 1.9, 6.5, 2.7)
    arrow(ax, 8.7, 3.0, 9.2, 3.0)
    arrow(ax, 7.6, 2.45, 5.9, 1.6, "rem -= fill", fs=9, ly=-0.25, dashed=True)
    ax.text(10.0, 1.6, "to P&L\n(1 cycle after\nbook done)", ha="center", fontsize=9.5, color=BLUE)
    save(fig, "matching_datapath.png")


def m2_block():
    fig, ax = canvas(13, 6.5)
    ax.text(6.5, 6.15, "Milestone 2 system (blue = Parth, red = Pierce)", ha="center", fontsize=15, weight="bold")
    box(ax, 1.3, 4.6, 2.0, 0.9, "market ROM", col=GREY)
    box(ax, 1.3, 2.4, 2.0, 0.9, "PS/2 keyboard", col=GREY)
    box(ax, 3.9, 4.6, 2.2, 0.9, "feed handler")
    box(ax, 3.9, 2.4, 2.2, 1.1, "ps2_rx ->", "kb_decoder -> order_entry")
    box(ax, 6.4, 3.5, 1.8, 1.0, "order", "arbiter")
    box(ax, 8.7, 3.5, 2.0, 1.0, "order book", "masks + RAM")
    box(ax, 11.2, 4.7, 2.0, 0.9, "strategy", col=RED)
    box(ax, 11.2, 3.3, 2.0, 0.9, "risk gate", col=RED)
    box(ax, 8.7, 1.5, 2.2, 0.9, "matching engine")
    box(ax, 11.2, 1.5, 2.0, 0.9, "P&L tracker", col=RED)
    box(ax, 8.7, 5.4, 2.0, 0.7, "VGA dashboard", col=RED, fs=11)
    arrow(ax, 2.3, 4.6, 2.8, 4.6)
    arrow(ax, 2.3, 2.4, 2.8, 2.4)
    arrow(ax, 5.0, 4.5, 5.5, 3.8)
    arrow(ax, 5.0, 2.5, 5.5, 3.2)
    arrow(ax, 7.3, 3.5, 7.7, 3.5)
    arrow(ax, 9.7, 3.8, 10.2, 4.6, "done", fs=9, lx=-0.2)
    arrow(ax, 11.2, 4.25, 11.2, 3.75)
    arrow(ax, 8.7, 3.0, 8.7, 1.95, "trade", fs=9, lx=0.4, ly=0)
    arrow(ax, 10.6, 2.85, 9.6, 1.9, "quotes", fs=9, lx=0.35, ly=0.15)
    arrow(ax, 9.8, 1.5, 10.2, 1.5, "fills", fs=9, ly=0.2)
    arrow(ax, 12.2, 1.9, 12.2, 2.9, "position", fs=9, lx=0.55, ly=0, dashed=True)
    arrow(ax, 8.7, 4.0, 8.7, 5.05)
    ax.text(3.9, 0.9, "HEX views: bot, market, depth, entry, fills  (KEY[2])", fontsize=10, ha="center", color=GREY)
    save(fig, "m2_block.png")


if __name__ == "__main__":
    with plt.xkcd(scale=0.8, length=120, randomness=2):
        plt.rcParams["font.family"] = ["Humor Sans", "Comic Sans MS", "DejaVu Sans"]
        book_datapath()
        arbiter_fsm()
        entry_fsm()
        matching_datapath()
        m2_block()
