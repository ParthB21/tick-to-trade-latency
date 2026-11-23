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
// Text (rows 192..239), font_rom glyphs drawn 2x (10x14 pixels, one per 16-pixel cell):
//   "POS +ddd"   at y = 196, white
//   "PNL +ddddd" at y = 218, green when P&L >= 0, red when negative (|P&L| shown up to 99999)
//
// The FSM never erases: it repaints every pixel (bar/text colour or black)
// over and over, so old bars and digits are overwritten automatically.
//   per level : ADDR_BID -> ADDR_ASK -> LATCH_ASK -> DRAW (3 rows x 320 pixels)
//   then TEXT : 48 rows x 320 pixels
//   per frame : 64 x (3 + 960) + 15,360 = 76,992 cycles = 1.54 ms at 50 MHz
// Quotes, position and P&L are latched at the start of each frame; bin2bcd turns
// position and P&L into digits (17 cycles) long before the text pass reads them.
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

    // from the P&L tracker
    input  signed [9:0]  position,
    input  signed [23:0] pnl,

    // to vga_adapter
    output reg [8:0]  x,
    output reg [7:0]  y,
    output reg [2:0]  colour,
    output            plot
);
    localparam S_ADDR_BID = 3'd0, S_ADDR_ASK = 3'd1, S_LATCH_ASK = 3'd2, S_DRAW = 3'd3, S_TEXT = 3'd4;

    localparam TOP_LEVEL  = 6'd63;
    localparam LAST_X     = 9'd319;
    localparam GAP_ROW    = 2'd2;      // dy of the black row between levels
    localparam CENTRE     = 9'd160;    // first ask pixel; bids end at CENTRE - 1
    localparam QTY_SHIFT  = 5;         // 32 shares per pixel
    localparam BAR_MAX    = 8'd159;
    localparam MARK_W     = 9'd8;
    localparam BID_MARK_X = 9'd8;
    localparam ASK_MARK_X = 9'd304;

    localparam LAST_Y     = 8'd239;
    localparam TEXT_X     = 9'd8;      // left edge of the first character cell
    localparam POS_Y      = 8'd196;    // top row of "POS ..."
    localparam PNL_Y      = 8'd218;    // top row of "PNL ..."
    localparam TEXT_H     = 8'd14;     // 7 glyph rows drawn 2x
    localparam GLYPH_W    = 3'd5;
    localparam PNL_SHOWN  = 17'd99999; // largest |P&L| that fits 5 digits

    localparam G_PLUS = 5'd10, G_MINUS = 5'd11, G_P = 5'd12, G_O = 5'd13,
               G_S = 5'd14, G_N = 5'd15, G_L = 5'd16, G_SPACE = 5'd31;

    localparam BLACK = 3'b000, GREEN = 3'b010, RED = 3'b100, YELLOW = 3'b110, WHITE = 3'b111;

    reg [2:0] state;
    reg [5:0] level;
    reg [1:0] dy;
    reg [7:0] bid_len, ask_len;

    // quotes latched once per frame so a frame never shows half-old, half-new markers
    reg       f_bid_live, f_ask_live;
    reg [5:0] f_bid_px,   f_ask_px;

    assign q_side  = (state == S_ADDR_ASK);
    assign q_level = level;
    assign plot    = (state == S_DRAW) || (state == S_TEXT);

    // ---------------- position / P&L digits ----------------
    wire frame_start = (state == S_ADDR_BID) && (level == TOP_LEVEL);
    reg  f_pos_neg, f_pnl_neg;
    wire [9:0]  pos_mag   = position[9] ? -position : position;       // -512 -> 512 fits unsigned
    wire [23:0] pnl_abs   = pnl[23] ? -pnl : pnl;
    wire [16:0] pnl_mag   = (pnl_abs > PNL_SHOWN) ? PNL_SHOWN : pnl_abs[16:0];
    wire [11:0] pos_bcd;
    wire [19:0] pnl_bcd;

    bin2bcd #(.BITS(10), .DIGITS(3)) u_pos_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(pos_mag), .bcd(pos_bcd));
    bin2bcd #(.BITS(17), .DIGITS(5)) u_pnl_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(pnl_mag), .bcd(pnl_bcd));

    // ---------------- text pixel ----------------
    wire [8:0] tx      = x - TEXT_X;                 // x < TEXT_X wraps to a cell past the text
    wire [4:0] slot    = tx[8:4];                    // 16-pixel character cell index
    wire [2:0] gcol    = tx[3:1];
    wire       in_pos  = (y >= POS_Y) && (y < POS_Y + TEXT_H);
    wire       in_pnl  = (y >= PNL_Y) && (y < PNL_Y + TEXT_H);
    wire [7:0] ty      = y - (in_pos ? POS_Y : PNL_Y);
    wire [2:0] grow    = ty[3:1];
    wire [4:0] pos_sign = f_pos_neg ? G_MINUS : G_PLUS;
    wire [4:0] pnl_sign = f_pnl_neg ? G_MINUS : G_PLUS;
    wire [4:0] font_bits;
    reg  [4:0] glyph;

    always @* begin
        glyph = G_SPACE;
        if (in_pos)
            case (slot)
                5'd0: glyph = G_P;    5'd1: glyph = G_O;    5'd2: glyph = G_S;
                5'd4: glyph = pos_sign;
                5'd5: glyph = {1'b0, pos_bcd[11:8]};
                5'd6: glyph = {1'b0, pos_bcd[7:4]};
                5'd7: glyph = {1'b0, pos_bcd[3:0]};
                default: glyph = G_SPACE;
            endcase
        else if (in_pnl)
            case (slot)
                5'd0: glyph = G_P;    5'd1: glyph = G_N;    5'd2: glyph = G_L;
                5'd4: glyph = pnl_sign;
                5'd5: glyph = {1'b0, pnl_bcd[19:16]};
                5'd6: glyph = {1'b0, pnl_bcd[15:12]};
                5'd7: glyph = {1'b0, pnl_bcd[11:8]};
                5'd8: glyph = {1'b0, pnl_bcd[7:4]};
                5'd9: glyph = {1'b0, pnl_bcd[3:0]};
                default: glyph = G_SPACE;
            endcase
    end

    font_rom u_font (.glyph(glyph), .row(grow), .bits(font_bits));

    wire       text_lit    = (gcol < GLYPH_W) && font_bits[GLYPH_W - 1 - gcol];
    wire [2:0] text_colour = !text_lit ? BLACK : in_pos ? WHITE : f_pnl_neg ? RED : GREEN;

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
        if (state == S_TEXT)
            colour = text_colour;
        else if (dy != GAP_ROW) begin
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
            f_pos_neg <= 1'b0; f_pnl_neg <= 1'b0;
        end else begin
            case (state)
                S_ADDR_BID: begin
                    if (frame_start) begin
                        f_bid_live <= our_bid_live; f_bid_px <= our_bid_px;
                        f_ask_live <= our_ask_live; f_ask_px <= our_ask_px;
                        f_pos_neg  <= position[9];  f_pnl_neg <= pnl[23];
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
                            level <= level - 1'b1; // 0 wraps to 63 for the next frame
                            y     <= y + 1'b1;     // after level 0 this is the first text row
                            state <= (level == 6'd0) ? S_TEXT : S_ADDR_BID;
                        end
                    end
                end
                S_TEXT: begin                      // plot = 1
                    if (x != LAST_X)
                        x <= x + 1'b1;
                    else begin
                        x <= 9'd0;
                        if (y != LAST_Y)
                            y <= y + 1'b1;
                        else begin                 // frame finished
                            y     <= 8'd0;
                            state <= S_ADDR_BID;
                        end
                    end
                end
                default: state <= S_ADDR_BID;      // unused codes 5..7
            endcase
        end
    end
endmodule
