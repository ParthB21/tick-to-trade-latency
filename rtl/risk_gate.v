// risk_gate.v  (Pierce)
// Checks every quote from the strategy before it goes to the exchange.
// All checks are parallel comparators; the result is registered, so
// quote_valid -> order_valid = 1 cycle.
//
// Checks (reject flag bit: what it blocks):
//   0 kill switch latched          : both sides, and pulls the resting quotes
//   1 quote not ok (book one-sided): both
//   2 size > max_size              : both
//   3 position + size > max_pos    : bid only  (buying would breach the long limit)
//   4 position - size < -max_pos   : ask only  (selling would breach the short limit)
//   5 crossing the market          : the offending side (bid >= best ask / ask <= best bid)
// A rejected side goes not-live, so a stale quote is never left resting.
// Reject flags are sticky until reset (shown on LEDR[5:0]), except bit 1: a one-sided book
// is not a violation, so it shows only the latest quote (every replay starts one-sided).
//
// Kill: the first cycle kill_sw is high, killed latches, both sides go
// not-live and order_valid pulses (the cancel). Only reset clears killed.
//
// best_bid/best_ask are read live, 2 cycles after the book's done pulse.
// The book cannot change again for at least 6 more cycles (8 cycles/message),
// so they are the same values the strategy saw.
module risk_gate (
    input             clk,
    input             resetn,
    input             kill_sw,          // synchronised switch level

    input             quote_valid,
    input             quote_ok,
    input      [5:0]  quote_bid_px,
    input      [5:0]  quote_ask_px,
    input      [7:0]  quote_size,

    input      [5:0]  best_bid,
    input             bid_valid,
    input      [5:0]  best_ask,
    input             ask_valid,

    input  signed [9:0] position,
    input      [8:0]  max_pos,
    input      [7:0]  max_size,

    output reg        order_valid,      // 1-cycle pulse: new orders out (latency stop)
    output reg        our_bid_live,
    output reg [5:0]  our_bid_px,
    output reg        our_ask_live,
    output reg [5:0]  our_ask_px,
    output reg [7:0]  our_size,
    output reg        killed,
    output reg [5:0]  reject
);
    localparam B_KILL = 0, B_NOT_OK = 1, B_SIZE = 2, B_LONG = 3, B_SHORT = 4, B_CROSS = 5;
    localparam [5:0] LIVE = 6'b000010;      // flags that follow the latest quote instead of latching

    // ---------------- checks (11-bit signed: +-511 +- 255 never overflows) ----------------
    wire signed [10:0] pos      = position;
    wire signed [10:0] size_s   = $signed({3'b000, quote_size});
    wire signed [10:0] limit    = $signed({2'b00, max_pos});
    wire signed [10:0] pos_buy  = pos + size_s;
    wire signed [10:0] pos_sell = pos - size_s;

    wire size_bad  = quote_size > max_size;
    wire long_bad  = pos_buy > limit;
    wire short_bad = pos_sell < -limit;
    wire bid_cross = ask_valid & (quote_bid_px >= best_ask);
    wire ask_cross = bid_valid & (quote_ask_px <= best_bid);

    wire common = ~killed & quote_ok & ~size_bad;
    wire bid_ok = common & ~long_bad  & ~bid_cross;
    wire ask_ok = common & ~short_bad & ~ask_cross;

    wire [5:0] flags;
    assign flags[B_KILL]   = killed;
    assign flags[B_NOT_OK] = ~quote_ok;
    assign flags[B_SIZE]   = size_bad;
    assign flags[B_LONG]   = long_bad;
    assign flags[B_SHORT]  = short_bad;
    assign flags[B_CROSS]  = bid_cross | ask_cross;

    always @(posedge clk) begin
        if (!resetn) begin
            order_valid <= 1'b0;
            our_bid_live <= 1'b0; our_bid_px <= 6'd0;
            our_ask_live <= 1'b0; our_ask_px <= 6'd0;
            our_size <= 8'd0; killed <= 1'b0; reject <= 6'd0;
        end else begin
            order_valid <= 1'b0;
            if (kill_sw && !killed) begin
                killed       <= 1'b1;
                our_bid_live <= 1'b0;
                our_ask_live <= 1'b0;
                order_valid  <= 1'b1;
                reject[B_KILL] <= 1'b1;
            end else if (quote_valid) begin
                our_bid_live <= bid_ok;  our_bid_px <= quote_bid_px;
                our_ask_live <= ask_ok;  our_ask_px <= quote_ask_px;
                our_size     <= quote_size;
                order_valid  <= 1'b1;
                reject       <= ((reject | flags) & ~LIVE) | (flags & LIVE);
            end
        end
    end
endmodule
