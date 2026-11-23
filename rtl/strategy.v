// strategy.v  (Pierce)
// Market-making strategy v2: quote a bid and an ask a fixed half-spread
// around the mid price, both shifted against our inventory (skew).
//
//   mid2   = best_bid + best_ask                       (mid in half-ticks, no fractions)
//   skew   = sign(position) * ((|position| * skew_k) >> 3)   ticks, rounds toward 0
//   bid_px = clamp(min(floor(mid) - half_spread - skew, best_ask - 1))   floor(mid) = mid2 >> 1
//   ask_px = clamp(max(ceil(mid)  + half_spread - skew, best_bid + 1))   ceil(mid)  = (mid2 + 1) >> 1
//   quote_ok = both sides present and the book is not crossed
// Long -> both quotes move down (sell more easily, buy less); short -> both move up.
// Skew never pushes a quote across the book: it stops at the best price that does
// not cross, so the side that reduces the position stays live instead of being
// rejected by the risk gate's crossing check.
//
// FSM:  IDLE --trigger--> CALC --> OUT --> IDLE
//   IDLE : on trigger (order book "done"), snapshot the inputs
//   CALC : register the quote computed from the snapshot
//   OUT  : quote_valid = 1 for one cycle
// trigger -> quote_valid = 2 cycles.
module strategy (
    input             clk,
    input             resetn,
    input             trigger,        // 1-cycle pulse: the book just changed

    input      [5:0]  best_bid,
    input             bid_valid,
    input      [5:0]  best_ask,
    input             ask_valid,
    input      [1:0]  half_spread,    // ticks either side of the mid
    input      [7:0]  size,           // shares per side
    input  signed [9:0] position,     // shares held, from the P&L tracker
    input      [2:0]  skew_k,         // skew = position * skew_k / 8 ticks; 0 = off

    output            quote_valid,    // 1-cycle pulse
    output reg        quote_ok,       // 0 = book one-sided or crossed, do not quote
    output reg [5:0]  quote_bid_px,
    output reg [5:0]  quote_ask_px,
    output reg [7:0]  quote_size
);
    localparam S_IDLE = 2'd0, S_CALC = 2'd1, S_OUT = 2'd2;
    localparam signed [11:0] PX_MIN = 12'sd0, PX_MAX = 12'sd63;
    localparam SKEW_SHIFT = 3;

    reg [1:0] state;
    assign quote_valid = (state == S_OUT);

    // ---------------- input snapshot ----------------
    reg [5:0] s_bid, s_ask;
    reg       s_bid_valid, s_ask_valid;
    reg [1:0] s_hs;
    reg [7:0] s_size;
    reg signed [9:0] s_pos;
    reg [2:0] s_k;

    // ---------------- datapath ----------------
    wire [6:0] mid2 = s_bid + s_ask;
    wire [6:0] mid2_up = mid2 + 1'b1;
    // magnitude first so a short position skews by the same ticks as an equal long one
    wire [9:0]  pos_mag  = s_pos[9] ? -s_pos : s_pos;          // -512 -> 512 fits unsigned
    wire [12:0] skew_mul = pos_mag * s_k;                       // the inventory-skew multiplier
    wire signed [11:0] skew_mag = $signed({2'b00, skew_mul[12:SKEW_SHIFT]});
    wire signed [11:0] skew     = s_pos[9] ? -skew_mag : skew_mag;
    // 12-bit signed so results below 0 stay negative instead of wrapping (max |skew| = 448)
    wire signed [11:0] bid_raw = $signed({6'd0, mid2[6:1]})    - $signed({10'd0, s_hs}) - skew;
    wire signed [11:0] ask_raw = $signed({6'd0, mid2_up[6:1]}) + $signed({10'd0, s_hs}) - skew;
    wire signed [11:0] bid_cap   = $signed({6'd0, s_ask}) - 12'sd1;   // highest bid that does not cross
    wire signed [11:0] ask_floor = $signed({6'd0, s_bid}) + 12'sd1;   // lowest ask that does not cross
    wire signed [11:0] bid_safe  = (bid_raw > bid_cap)   ? bid_cap   : bid_raw;
    wire signed [11:0] ask_safe  = (ask_raw < ask_floor) ? ask_floor : ask_raw;

    function [5:0] clamp_px(input signed [11:0] px);
        clamp_px = (px < PX_MIN) ? 6'd0 : (px > PX_MAX) ? 6'd63 : px[5:0];
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_IDLE;
            s_bid <= 6'd0; s_ask <= 6'd0; s_bid_valid <= 1'b0; s_ask_valid <= 1'b0;
            s_hs <= 2'd0; s_size <= 8'd0; s_pos <= 10'sd0; s_k <= 3'd0;
            quote_ok <= 1'b0; quote_bid_px <= 6'd0; quote_ask_px <= 6'd0; quote_size <= 8'd0;
        end else begin
            case (state)
                S_IDLE: if (trigger) begin
                    s_bid <= best_bid; s_bid_valid <= bid_valid;
                    s_ask <= best_ask; s_ask_valid <= ask_valid;
                    s_hs  <= half_spread; s_size <= size;
                    s_pos <= position;    s_k    <= skew_k;
                    state <= S_CALC;
                end
                S_CALC: begin
                    quote_ok     <= s_bid_valid & s_ask_valid & (s_bid < s_ask);
                    quote_bid_px <= clamp_px(bid_safe);
                    quote_ask_px <= clamp_px(ask_safe);
                    quote_size   <= s_size;
                    state <= S_OUT;
                end
                default: state <= S_IDLE;   // S_OUT: quote_valid is high this cycle
            endcase
        end
    end
endmodule
