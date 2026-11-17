// dashboard.v  (Pierce)
// VGA drawing FSM for the order book ladder, 320x240, 3-bit colour.
// Drives the course vga_adapter (x, y, colour, plot) and reads the book
// through order_book's query port (q_side, q_level -> q_qty, 1-cycle latency).
//
// Layout (rows 0..191, level 63 at the top, 3 rows per level, 3rd row black gap):
//   bids : green bar ending at x = 159, growing left
//   asks : red bar starting at x = 160, growing right
//   bar length = min(qty >> 5, 159) pixels, at least 1 pixel if qty > 0
//   our live bid / ask : yellow 8-pixel marker at x = 8..15 / x = 304..311
// Rows 192..239 are left as the adapter's background (text goes there in M2).
//
// The FSM never erases: it repaints every ladder pixel (bar colour or black)
// over and over, so old bars are overwritten automatically.
//   per level : ADDR_BID -> ADDR_ASK -> LATCH_ASK -> DRAW (3 rows x 320 pixels)
//   per frame : 64 x (3 + 960) = 61,632 cycles = 1.23 ms at 50 MHz
module dashboard (
    input             clk,
    input             resetn,

    // order book query port
    output            q_side,          // 0 = bid, 1 = ask
    output     [5:0]  q_level,
    input      [12:0] q_qty,

    // our resting quotes (from the risk gate)
    input             our_bid_live,
    input      [5:0]  our_bid_px,
    input             our_ask_live,
    input      [5:0]  our_ask_px,

    // to vga_adapter
    output reg [8:0]  x,
    output reg [7:0]  y,
    output reg [2:0]  colour,
    output            plot
);
    localparam S_ADDR_BID = 2'd0, S_ADDR_ASK = 2'd1, S_LATCH_ASK = 2'd2, S_DRAW = 2'd3;

    localparam TOP_LEVEL  = 6'd63;
    localparam LAST_X     = 9'd319;
    localparam GAP_ROW    = 2'd2;      // dy of the black row between levels
    localparam CENTRE     = 9'd160;    // first ask pixel; bids end at CENTRE - 1
    localparam QTY_SHIFT  = 5;         // 32 shares per pixel
    localparam BAR_MAX    = 8'd159;
    localparam MARK_W     = 9'd8;
    localparam BID_MARK_X = 9'd8;
    localparam ASK_MARK_X = 9'd304;

    localparam BLACK = 3'b000, GREEN = 3'b010, RED = 3'b100, YELLOW = 3'b110;

    reg [1:0] state;
    reg [5:0] level;
    reg [1:0] dy;
    reg [7:0] bid_len, ask_len;

    // quotes latched once per frame so a frame never shows half-old, half-new markers
    reg       f_bid_live, f_ask_live;
    reg [5:0] f_bid_px,   f_ask_px;

    assign q_side  = (state == S_ADDR_ASK);
    assign q_level = level;
    assign plot    = (state == S_DRAW);

    function [7:0] bar_len(input [12:0] qty);
        reg [7:0] scaled;
        begin
            scaled  = qty >> QTY_SHIFT;
            bar_len = (qty == 13'd0)      ? 8'd0
                    : (scaled == 8'd0)    ? 8'd1
                    : (scaled > BAR_MAX)  ? BAR_MAX
                    :                       scaled;
        end
    endfunction

    // ---------------- pixel colour (combinational from registers) ----------------
    always @* begin
        colour = BLACK;
        if (dy != GAP_ROW) begin
            if (x < CENTRE && (CENTRE - x) <= bid_len)          colour = GREEN;
            if (x >= CENTRE && (x - CENTRE) < ask_len)          colour = RED;
            if (f_bid_live && level == f_bid_px &&
                x >= BID_MARK_X && x < BID_MARK_X + MARK_W)     colour = YELLOW;
            if (f_ask_live && level == f_ask_px &&
                x >= ASK_MARK_X && x < ASK_MARK_X + MARK_W)     colour = YELLOW;
        end
    end

    // ---------------- control FSM + counters ----------------
    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_ADDR_BID;
            level <= TOP_LEVEL; dy <= 2'd0; x <= 9'd0; y <= 8'd0;
            bid_len <= 8'd0; ask_len <= 8'd0;
            f_bid_live <= 1'b0; f_bid_px <= 6'd0; f_ask_live <= 1'b0; f_ask_px <= 6'd0;
        end else begin
            case (state)
                S_ADDR_BID: begin
                    if (level == TOP_LEVEL) begin
                        f_bid_live <= our_bid_live; f_bid_px <= our_bid_px;
                        f_ask_live <= our_ask_live; f_ask_px <= our_ask_px;
                    end
                    state <= S_ADDR_ASK;
                end
                S_ADDR_ASK: begin                  // q_qty = bid qty (address from last cycle)
                    bid_len <= bar_len(q_qty);
                    state   <= S_LATCH_ASK;
                end
                S_LATCH_ASK: begin                 // q_qty = ask qty
                    ask_len <= bar_len(q_qty);
                    state   <= S_DRAW;
                end
                S_DRAW: begin                      // plot = 1: (x, y, colour) written this edge
                    if (x != LAST_X)
                        x <= x + 1'b1;
                    else begin
                        x <= 9'd0;
                        if (dy != GAP_ROW) begin
                            dy <= dy + 1'b1;
                            y  <= y + 1'b1;
                        end else begin             // level finished
                            dy    <= 2'd0;
                            level <= level - 1'b1; // 0 wraps to 63: next frame
                            y     <= (level == 6'd0) ? 8'd0 : y + 1'b1;
                            state <= S_ADDR_BID;
                        end
                    end
                end
            endcase
        end
    end
endmodule
