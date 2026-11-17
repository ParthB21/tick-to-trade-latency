// strategy.v  (Pierce)
// Market-making strategy v1: quote a bid and an ask a fixed half-spread
// around the mid price. No inventory skew yet (v2, after M1).
//
//   mid2   = best_bid + best_ask                (mid in half-ticks, no fractions)
//   bid_px = clamp(floor(mid) - half_spread)    floor(mid) = mid2 >> 1
//   ask_px = clamp(ceil(mid)  + half_spread)    ceil(mid)  = (mid2 + 1) >> 1
//   quote_ok = both sides present and the book is not crossed
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

    output            quote_valid,    // 1-cycle pulse
    output reg        quote_ok,       // 0 = book one-sided or crossed, do not quote
    output reg [5:0]  quote_bid_px,
    output reg [5:0]  quote_ask_px,
    output reg [7:0]  quote_size
);
    localparam S_IDLE = 2'd0, S_CALC = 2'd1, S_OUT = 2'd2;
    localparam signed [8:0] PX_MIN = 9'sd0, PX_MAX = 9'sd63;

    reg [1:0] state;
    assign quote_valid = (state == S_OUT);

    // ---------------- input snapshot ----------------
    reg [5:0] s_bid, s_ask;
    reg       s_bid_valid, s_ask_valid;
    reg [1:0] s_hs;
    reg [7:0] s_size;

    // ---------------- datapath ----------------
    wire [6:0] mid2 = s_bid + s_ask;
    // 9-bit signed so a result below 0 stays negative instead of wrapping to 6x
    wire signed [8:0] bid_raw = $signed({3'b000, mid2[6:1]}) - $signed({7'd0, s_hs});
    wire [6:0]        mid2_up = mid2 + 1'b1;
    wire signed [8:0] ask_raw = $signed({3'b000, mid2_up[6:1]}) + $signed({7'd0, s_hs});

    function [5:0] clamp_px(input signed [8:0] px);
        clamp_px = (px < PX_MIN) ? 6'd0 : (px > PX_MAX) ? 6'd63 : px[5:0];
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_IDLE;
            s_bid <= 6'd0; s_ask <= 6'd0; s_bid_valid <= 1'b0; s_ask_valid <= 1'b0;
            s_hs <= 2'd0; s_size <= 8'd0;
            quote_ok <= 1'b0; quote_bid_px <= 6'd0; quote_ask_px <= 6'd0; quote_size <= 8'd0;
        end else begin
            case (state)
                S_IDLE: if (trigger) begin
                    s_bid <= best_bid; s_bid_valid <= bid_valid;
                    s_ask <= best_ask; s_ask_valid <= ask_valid;
                    s_hs  <= half_spread; s_size <= size;
                    state <= S_CALC;
                end
                S_CALC: begin
                    quote_ok     <= s_bid_valid & s_ask_valid & (s_bid < s_ask);
                    quote_bid_px <= clamp_px(bid_raw);
                    quote_ask_px <= clamp_px(ask_raw);
                    quote_size   <= s_size;
                    state <= S_OUT;
                end
                default: state <= S_IDLE;   // S_OUT: quote_valid is high this cycle
            endcase
        end
    end
endmodule
