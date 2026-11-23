// pnl_tracker.v  (Pierce)
// Position and P&L accumulators, driven by fills from the matching engine.
//
// Fill interface (from the matching engine, one fill per pulse):
//   fill_valid : 1-cycle pulse
//   fill_side  : 0 = our bid was hit (we bought), 1 = our ask was lifted (we sold)
//   fill_px    : price level the fill happened at (our quote price)
//   fill_qty   : shares filled
//
//   buy  : position += qty, cash -= px * qty
//   sell : position -= qty, cash += px * qty
//   mark : floor of the mid, updated whenever both sides of the book exist
//          (held when one side is empty)
//   pnl  = cash + position * mark   in ticks x shares, registered (1 cycle behind)
//
// Position is not saturated: the risk gate keeps |position| <= max_pos + max_size,
// far inside 10 bits. Cash is 24-bit signed (+-8.3M), each fill moves it at most
// 63 * 255 = 16,065, and because position is bounded cash stays near -position * price + pnl.
module pnl_tracker (
    input                    clk,
    input                    resetn,

    input                    fill_valid,
    input                    fill_side,
    input             [5:0]  fill_px,
    input             [7:0]  fill_qty,

    input             [5:0]  best_bid,
    input                    bid_valid,
    input             [5:0]  best_ask,
    input                    ask_valid,

    output reg signed [9:0]  position,
    output reg signed [23:0] pnl
);
    localparam BUY = 1'b0;

    reg signed [23:0] cash;
    reg        [5:0]  mark;

    wire        [13:0] notional = fill_px * fill_qty;        // at most 63 * 255 = 16,065
    wire signed [9:0]  qty_s    = $signed({2'b00, fill_qty});
    wire signed [23:0] cost     = $signed({10'd0, notional});
    wire        [6:0]  mid2     = best_bid + best_ask;

    always @(posedge clk) begin
        if (!resetn) begin
            position <= 10'sd0; cash <= 24'sd0; mark <= 6'd0; pnl <= 24'sd0;
        end else begin
            pnl <= cash + position * $signed({1'b0, mark});
            if (fill_valid) begin
                if (fill_side == BUY) begin
                    position <= position + qty_s;
                    cash     <= cash - cost;
                end else begin
                    position <= position - qty_s;
                    cash     <= cash + cost;
                end
            end
            if (bid_valid && ask_valid) mark <= mid2[6:1];
        end
    end
endmodule
