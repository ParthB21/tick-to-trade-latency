// matching_engine.v  (Parth, M2)
// Simulated exchange: decides when the market trades with OUR resting quotes.
//
// The replayed market data says "resting order X traded qty Q" (the order book
// turns that into trade_valid / trade_side / trade_price / trade_qty, where
// trade_side is the side of the RESTING order that was hit). Our own quotes are
// not in the replayed book, so this block checks whether the trade would have
// reached us first:
//
//   trade on the BID side at price p : someone sold down to p.
//        Our bid fills if it is live and our_bid_px >= p   ("at or through")
//   trade on the ASK side at price p : someone bought up to p.
//        Our ask fills if it is live and our_ask_px <= p
//
//   fill price = our price, fill qty = min(trade_qty, what is left of our quote)
//
// Our quote size is reloaded from the risk gate on every order_valid (a new or
// refreshed quote is a fresh order). Fills reduce what is left, so one quote
// can never fill more than its size. Our fills do not change the replayed book
// (no market impact), which is the usual assumption when replaying recorded data.
//
// Timing: trade_valid (= book done) -> fill_valid one cycle later. The risk gate's
// next order_valid comes 3 cycles after the book's done, so the check always uses
// the quote that was resting BEFORE this market message, which is what a real
// exchange would do. Datapath only (comparators + subtractors + registers), no FSM.
module matching_engine (
    input             clk,
    input             resetn,

    // trade event from the order book (1-cycle pulse together with done)
    input             trade_valid,
    input             trade_side,       // side of the resting order that traded: 0 bid, 1 ask
    input      [5:0]  trade_price,
    input      [12:0] trade_qty,

    // our resting quotes, from the risk gate
    input             order_valid,      // 1-cycle pulse: quotes below were just (re)sent
    input             our_bid_live,
    input      [5:0]  our_bid_px,
    input             our_ask_live,
    input      [5:0]  our_ask_px,
    input      [7:0]  our_size,

    // fills, to the P&L tracker (Pierce)
    output reg        fill_valid,       // 1-cycle pulse
    output reg        fill_side,        // 0 = we bought (our bid filled), 1 = we sold
    output reg [5:0]  fill_px,
    output reg [7:0]  fill_qty,
    output reg [15:0] fill_count,       // fills since reset (for the HEX fills view)

    output reg [7:0]  bid_rem,          // shares left on our bid / ask quote
    output reg [7:0]  ask_rem
);
    // ---------------- compare (combinational) ----------------
    wire bid_hit = trade_valid & ~trade_side & (bid_rem != 8'd0) & (our_bid_px >= trade_price);
    wire ask_hit = trade_valid &  trade_side & (ask_rem != 8'd0) & (our_ask_px <= trade_price);

    // min(trade_qty, remaining): trade_qty is 13 bits, remaining 8 bits
    wire [7:0] bid_q = (trade_qty < {5'd0, bid_rem}) ? trade_qty[7:0] : bid_rem;
    wire [7:0] ask_q = (trade_qty < {5'd0, ask_rem}) ? trade_qty[7:0] : ask_rem;

    // ---------------- registers ----------------
    always @(posedge clk) begin
        if (!resetn) begin
            fill_valid <= 1'b0; fill_side <= 1'b0; fill_px <= 6'd0; fill_qty <= 8'd0;
            fill_count <= 16'd0;
            bid_rem <= 8'd0; ask_rem <= 8'd0;
        end else begin
            fill_valid <= bid_hit | ask_hit;
            if (bid_hit) begin
                fill_side <= 1'b0; fill_px <= our_bid_px; fill_qty <= bid_q;
            end else if (ask_hit) begin
                fill_side <= 1'b1; fill_px <= our_ask_px; fill_qty <= ask_q;
            end
            if (bid_hit | ask_hit) fill_count <= fill_count + 1'b1;

            // a new quote replaces what was left; otherwise a fill uses some up
            if (order_valid) begin
                bid_rem <= our_bid_live ? our_size : 8'd0;
                ask_rem <= our_ask_live ? our_size : 8'd0;
            end else begin
                if (bid_hit) bid_rem <= bid_rem - bid_q;
                if (ask_hit) ask_rem <= ask_rem - ask_q;
            end
        end
    end
endmodule
