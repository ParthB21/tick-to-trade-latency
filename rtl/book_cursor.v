// book_cursor.v  (Pierce, M2)
// Price-level cursor for the VGA ladder, moved with the PS/2 arrow keys.
//   Up    : next level ABOVE the cursor that has a bar (bid or ask); stays if there is none
//   Down  : next level BELOW the cursor that has a bar; stays if there is none
//   Left  : jump to the best bid   (stays if there are no bids)
//   Right : jump to the best ask   (stays if there are no asks)
// The dashboard shows the cursor's price, side and shares in the top-right corner.
// Holding an arrow repeats it (keyboard typematic), so the cursor walks bar to bar.
module book_cursor #(
    parameter [5:0] START = 6'd32
) (
    input             clk,
    input             resetn,
    input             key_valid,
    input      [4:0]  key_code,
    input      [63:0] bid_mask,
    input      [63:0] ask_mask,
    input      [5:0]  best_bid,
    input             bid_valid,
    input      [5:0]  best_ask,
    input             ask_valid,
    output reg [5:0]  cursor
);
    localparam K_UP = 5'd18, K_DOWN = 5'd19, K_LEFT = 5'd20, K_RIGHT = 5'd21;

    wire [63:0] bars  = bid_mask | ask_mask;
    // 2 << 63 overflows to 0, so at the top level "above" is empty, as it should be
    wire [63:0] above = bars & ~((64'd2 << cursor) - 64'd1);
    wire [63:0] below = bars &  ((64'd1 << cursor) - 64'd1);
    wire [5:0]  up_idx, down_idx;
    wire        up_ok, down_ok;

    prio_enc64 #(.HIGHEST(0)) u_up   (.in(above), .idx(up_idx),   .valid(up_ok));
    prio_enc64 #(.HIGHEST(1)) u_down (.in(below), .idx(down_idx), .valid(down_ok));

    always @(posedge clk) begin
        if (!resetn)
            cursor <= START;
        else if (key_valid)
            case (key_code)
                K_UP:    if (up_ok)     cursor <= up_idx;
                K_DOWN:  if (down_ok)   cursor <= down_idx;
                K_LEFT:  if (bid_valid) cursor <= best_bid;
                K_RIGHT: if (ask_valid) cursor <= best_ask;
                default: ;
            endcase
    end
endmodule
