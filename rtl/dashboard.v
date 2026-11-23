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
//   arrow-key cursor   : the bar(s) on the cursor level are drawn white instead of green / red
//   cursor readout     : top-right black box (x >= 226, rows 0..10) with one text line
//                        "BID pp QTY qqqq" (green) / "ASK pp QTY qqqq" (red) / "--- pp QTY 0000"
//                        (level emptied under the cursor); "--- -- QTY 0000" while the cursor
//                        is off (reset until the first arrow key), and no white bar
//
// Text is drawn for a 16:9 monitor that stretches the 4:3 picture 4/3 wider: glyphs are
// 5 pixels wide in 6-pixel cells and 9 rows tall (font rows 2 and 4 drawn twice), so after
// the stretch they look like the 5x7 font at its normal shape.
// Text panel (rows 194..233), 4 lines, line k at rows 194 + 10k, 52 cells per line:
//   0 white  : BOOK BID bb ASK aa SPREAD ss MSGS mmmm      market best bid/ask, spread, ROM msgs
//   1 yellow : BOT  BID bb ASK aa SPREAD ss SIZE z SKEW ON   our quotes and our spread ("--" = not live)
//   2        : POS sddd PNL sddddd FILLS ffff LAST SELL qqq AT pp
//              POS white; PNL green (>= 0) / red (< 0); fills cyan
//   3        : KEYS c f dddd  RISK OK / KILL SIDE SIZE LONG SHORT CROSS
//              keys white (red on ERR); risk green when OK, red with the sticky reject flags
// Every number is converted with bin2bcd (sequential, started at the frame start).
//
// The FSM never erases: it repaints every pixel (bar/text colour or black)
// over and over, so old bars and digits are overwritten automatically.
//   per level : ADDR_BID -> ADDR_ASK -> LATCH_ASK -> DRAW (3 rows x 320 pixels)
//   then TEXT : 48 rows x 320 pixels
//   per frame : 64 x (3 + 960) + 15,360 = 76,992 cycles = 1.54 ms at 50 MHz
// Everything shown is latched at the start of each frame (bin2bcd takes at most 17 cycles),
// long before the text pass reads it, so a frame never mixes old and new values.
// The cursor readout is drawn at the top of the frame, before the ladder reaches the
// cursor level, so it shows the shares captured on the PREVIOUS frame (1.5 ms old).
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

    // status panel (M2)
    input      [5:0]  best_bid,          // order book top
    input             bid_valid,
    input      [5:0]  best_ask,
    input             ask_valid,
    input      [10:0] msg_count,         // ROM messages processed
    input      [7:0]  our_size,          // risk gate quote size
    input             skew_on,           // SW[2]
    input      [15:0] fill_count,        // matching engine
    input             fill_side,         // last fill: 0 bought, 1 sold
    input      [5:0]  fill_px,
    input      [7:0]  fill_qty,
    input      [29:0] entry_disp,        // order entry display codes (seg7 codes, HEX5 first)
    input      [5:0]  reject,            // risk gate sticky reject flags
    input      [5:0]  cursor,            // arrow-key cursor level (book_cursor)
    input             cursor_active,     // 0 = cursor off: no white bar, blank readout

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
    localparam TEXT_X     = 9'd4;      // left edge of the first panel cell
    localparam TEXT_Y     = 8'd194;    // top row of panel line 0; line k starts at 194 + 10k
    localparam READ_X     = 9'd230;    // left edge of the first readout cell
    localparam READ_Y     = 8'd1;      // top row of the readout line
    localparam BOX_X      = 9'd226;    // readout box: x >= BOX_X, y <= BOX_LAST_Y
    localparam BOX_LAST_Y = 8'd10;
    localparam GLYPH_W    = 3'd5;
    localparam GLYPH_H    = 4'd9;      // drawn rows per glyph; row 9 of a line is the gap
    localparam LINE_H     = 8'd10;
    localparam DIV6_MUL   = 8'd171;    // floor(t / 6) = (t * 171) >> 10 for t <= 315
    localparam PNL_SHOWN  = 17'd99999; // largest |P&L| that fits 5 digits
    localparam FILLS_SHOWN = 14'd9999;

    // font_rom glyph codes (python/font.py): 0..9 digits
    localparam [5:0] G_PLUS = 6'd10, G_MINUS = 6'd11,
        G_A = 6'd12, G_B = 6'd13, G_C = 6'd14, G_D = 6'd15, G_E = 6'd16, G_F = 6'd17, G_G = 6'd18,
        G_H = 6'd19, G_I = 6'd20, G_K = 6'd21, G_L = 6'd22, G_M = 6'd23, G_N = 6'd24, G_O = 6'd25,
        G_P = 6'd26, G_Q = 6'd27, G_R = 6'd28, G_S = 6'd29, G_T = 6'd30, G_U = 6'd31, G_W = 6'd32,
        G_Y = 6'd33, G_Z = 6'd34, G_SP = 6'd63;

    localparam BLACK = 3'b000, GREEN = 3'b010, RED = 3'b100, YELLOW = 3'b110, WHITE = 3'b111,
               CYAN = 3'b011;

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

    // ---------------- panel values, latched / converted at the frame start ----------------
    wire frame_start = (state == S_ADDR_BID) && (level == TOP_LEVEL);
    reg  f_pos_neg, f_pnl_neg;
    reg  f_book_bid, f_book_ask, f_skew, f_has_fill, f_fill_side;
    reg  [3:0]  f_size;
    reg  [29:0] f_keys;
    reg  [5:0]  f_reject;

    // cursor: f_cursor is this frame's level (marker + capture); the readout shows the capture
    // of the previous frame (cap_*): its BCD and side flags are taken at the frame start
    reg  [5:0]  f_cursor, cap_level;
    reg  [12:0] cap_bid, cap_ask;
    reg         d_is_bid, d_is_ask;
    reg         f_cur_on, d_cur_on;      // this frame's cursor state / the readout's (previous frame)

    wire [9:0]  pos_mag   = position[9] ? -position : position;       // -512 -> 512 fits unsigned
    wire [23:0] pnl_abs   = pnl[23] ? -pnl : pnl;
    wire [16:0] pnl_mag   = (pnl_abs > PNL_SHOWN) ? PNL_SHOWN : pnl_abs[16:0];
    wire [5:0]  spread    = best_ask - best_bid;                       // only shown when both sides exist
    wire [5:0]  our_spread = our_ask_px - our_bid_px;                  // only shown when both quotes are live
    wire [13:0] fills_mag = (fill_count > {2'b00, FILLS_SHOWN}) ? FILLS_SHOWN : fill_count[13:0];
    wire [12:0] cap_qty   = (cap_bid != 13'd0) ? cap_bid : cap_ask;    // max 8191 fits 4 digits

    wire [11:0] pos_bcd, fq_bcd;
    wire [19:0] pnl_bcd;
    wire [7:0]  bb_bcd, ba_bcd, sp_bcd, ob_bcd, oa_bcd, os_bcd, fp_bcd, cl_bcd;
    wire [15:0] msg_bcd, fc_bcd, cq_bcd;

    bin2bcd #(.BITS(10), .DIGITS(3)) u_pos_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(pos_mag), .bcd(pos_bcd));
    bin2bcd #(.BITS(17), .DIGITS(5)) u_pnl_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(pnl_mag), .bcd(pnl_bcd));
    bin2bcd #(.BITS(6), .DIGITS(2)) u_bb_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(best_bid), .bcd(bb_bcd));
    bin2bcd #(.BITS(6), .DIGITS(2)) u_ba_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(best_ask), .bcd(ba_bcd));
    bin2bcd #(.BITS(6), .DIGITS(2)) u_sp_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(spread), .bcd(sp_bcd));
    bin2bcd #(.BITS(11), .DIGITS(4)) u_msg_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(msg_count), .bcd(msg_bcd));
    bin2bcd #(.BITS(6), .DIGITS(2)) u_ob_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(our_bid_px), .bcd(ob_bcd));
    bin2bcd #(.BITS(6), .DIGITS(2)) u_oa_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(our_ask_px), .bcd(oa_bcd));
    bin2bcd #(.BITS(6), .DIGITS(2)) u_os_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(our_spread), .bcd(os_bcd));
    bin2bcd #(.BITS(14), .DIGITS(4)) u_fc_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(fills_mag), .bcd(fc_bcd));
    bin2bcd #(.BITS(8), .DIGITS(3)) u_fq_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(fill_qty), .bcd(fq_bcd));
    bin2bcd #(.BITS(6), .DIGITS(2)) u_fp_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(fill_px), .bcd(fp_bcd));
    bin2bcd #(.BITS(6), .DIGITS(2)) u_cl_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(cap_level), .bcd(cl_bcd));
    bin2bcd #(.BITS(13), .DIGITS(4)) u_cq_bcd (
        .clk(clk), .resetn(resetn), .start(frame_start), .value(cap_qty), .bcd(cq_bcd));

    // ---------------- text pixel ----------------
    function [5:0] dg(input [3:0] d); dg = {2'b00, d}; endfunction       // BCD digit -> glyph

    // order-entry display code (seg7.v codes) -> glyph
    function [5:0] seg_glyph(input [4:0] c);
        case (c)
            5'd0, 5'd1, 5'd2, 5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8, 5'd9: seg_glyph = {1'b0, c};
            5'd10: seg_glyph = G_MINUS;
            5'd16: seg_glyph = G_B;   5'd17: seg_glyph = G_S;   5'd18: seg_glyph = G_C;
            5'd19: seg_glyph = G_T;   5'd20: seg_glyph = G_E;   5'd21: seg_glyph = G_R;
            5'd22: seg_glyph = G_D;   5'd23: seg_glyph = G_P;   5'd24: seg_glyph = G_Q;
            5'd25: seg_glyph = G_F;
            default: seg_glyph = G_SP;
        endcase
    endfunction

    // 9 drawn rows from the 7 font rows: rows 2 and 4 twice, so 1-pixel bars stay 1 pixel
    function [2:0] font_row(input [3:0] r);
        case (r)
            4'd0: font_row = 3'd0;  4'd1: font_row = 3'd1;  4'd2, 4'd3: font_row = 3'd2;
            4'd4: font_row = 3'd3;  4'd5, 4'd6: font_row = 3'd4;
            4'd7: font_row = 3'd5;  default: font_row = 3'd6;
        endcase
    endfunction

    // the panel and the readout share the cell divider: x relative to their first cell
    wire        in_text = (state == S_TEXT);
    wire [8:0]  tx      = x - (in_text ? TEXT_X : READ_X);   // x left of the first cell wraps past the text
    wire [16:0] tx_mul  = tx * DIV6_MUL;
    wire [6:0]  slot    = tx_mul[16:10];                     // 6-pixel cell index
    wire [8:0]  slot6   = {slot, 2'b00} + {1'b0, slot, 1'b0};
    wire [8:0]  gcol    = tx - slot6;                        // pixel inside the cell, 0..5

    wire [7:0]  ty    = y - TEXT_Y;                          // rows above the panel wrap past it
    wire [2:0]  tline = (ty < 8'd10) ? 3'd0 : (ty < 8'd20) ? 3'd1 : (ty < 8'd30) ? 3'd2
                      : (ty < 8'd40) ? 3'd3 : 3'd7;
    wire [7:0]  trow8 = ty - {tline[1:0], 3'b000} - {tline[1:0], 1'b0};   // ty - 10 * tline
    wire [7:0]  ry    = y - READ_Y;                          // readout glyph row (row 0 wraps)
    wire [3:0]  grow  = in_text ? trow8[3:0] : ry[3:0];
    wire        row_ok = in_text ? (tline != 3'd7 && trow8 < GLYPH_H) : (ry < GLYPH_H);

    wire [5:0] pos_sign = f_pos_neg ? G_MINUS : G_PLUS;
    wire [5:0] pnl_sign = f_pnl_neg ? G_MINUS : G_PLUS;
    wire       two_sided = f_book_bid & f_book_ask;
    wire       our_two   = f_bid_live & f_ask_live;
    wire       keys_err  = (f_keys[29:25] == 5'd20);  // entry shows "E r r"
    wire [4:0] font_bits;
    reg  [5:0] glyph, rglyph;

    always @* begin
        glyph = G_SP;
        case (tline)
            // BOOK BID bb ASK aa SPREAD ss MSGS mmmm
            3'd0: case (slot)
                7'd0: glyph = G_B;  7'd1: glyph = G_O;  7'd2: glyph = G_O;  7'd3: glyph = G_K;
                7'd5: glyph = G_B;  7'd6: glyph = G_I;  7'd7: glyph = G_D;
                7'd9:  glyph = f_book_bid ? dg(bb_bcd[7:4]) : G_MINUS;
                7'd10: glyph = f_book_bid ? dg(bb_bcd[3:0]) : G_MINUS;
                7'd12: glyph = G_A; 7'd13: glyph = G_S; 7'd14: glyph = G_K;
                7'd16: glyph = f_book_ask ? dg(ba_bcd[7:4]) : G_MINUS;
                7'd17: glyph = f_book_ask ? dg(ba_bcd[3:0]) : G_MINUS;
                7'd19: glyph = G_S; 7'd20: glyph = G_P; 7'd21: glyph = G_R; 7'd22: glyph = G_E;
                7'd23: glyph = G_A; 7'd24: glyph = G_D;
                7'd26: glyph = two_sided ? dg(sp_bcd[7:4]) : G_MINUS;
                7'd27: glyph = two_sided ? dg(sp_bcd[3:0]) : G_MINUS;
                7'd29: glyph = G_M; 7'd30: glyph = G_S; 7'd31: glyph = G_G; 7'd32: glyph = G_S;
                7'd34: glyph = dg(msg_bcd[15:12]); 7'd35: glyph = dg(msg_bcd[11:8]);
                7'd36: glyph = dg(msg_bcd[7:4]);   7'd37: glyph = dg(msg_bcd[3:0]);
                default: glyph = G_SP;
            endcase
            // BOT  BID bb ASK aa SPREAD ss SIZE z SKEW ON / OFF
            3'd1: case (slot)
                7'd0: glyph = G_B;  7'd1: glyph = G_O;  7'd2: glyph = G_T;
                7'd5: glyph = G_B;  7'd6: glyph = G_I;  7'd7: glyph = G_D;
                7'd9:  glyph = f_bid_live ? dg(ob_bcd[7:4]) : G_MINUS;
                7'd10: glyph = f_bid_live ? dg(ob_bcd[3:0]) : G_MINUS;
                7'd12: glyph = G_A; 7'd13: glyph = G_S; 7'd14: glyph = G_K;
                7'd16: glyph = f_ask_live ? dg(oa_bcd[7:4]) : G_MINUS;
                7'd17: glyph = f_ask_live ? dg(oa_bcd[3:0]) : G_MINUS;
                7'd19: glyph = G_S; 7'd20: glyph = G_P; 7'd21: glyph = G_R; 7'd22: glyph = G_E;
                7'd23: glyph = G_A; 7'd24: glyph = G_D;
                7'd26: glyph = our_two ? dg(os_bcd[7:4]) : G_MINUS;
                7'd27: glyph = our_two ? dg(os_bcd[3:0]) : G_MINUS;
                7'd29: glyph = G_S; 7'd30: glyph = G_I; 7'd31: glyph = G_Z; 7'd32: glyph = G_E;
                7'd34: glyph = dg(f_size);
                7'd36: glyph = G_S; 7'd37: glyph = G_K; 7'd38: glyph = G_E; 7'd39: glyph = G_W;
                7'd41: glyph = G_O;
                7'd42: glyph = f_skew ? G_N : G_F;
                7'd43: glyph = f_skew ? G_SP : G_F;
                default: glyph = G_SP;
            endcase
            // POS sddd PNL sddddd FILLS ffff LAST SELL qqq AT pp   (LAST... only after the first fill)
            3'd2: case (slot)
                7'd0: glyph = G_P;  7'd1: glyph = G_O;  7'd2: glyph = G_S;
                7'd4: glyph = pos_sign;
                7'd5: glyph = dg(pos_bcd[11:8]); 7'd6: glyph = dg(pos_bcd[7:4]); 7'd7: glyph = dg(pos_bcd[3:0]);
                7'd9: glyph = G_P;  7'd10: glyph = G_N; 7'd11: glyph = G_L;
                7'd13: glyph = pnl_sign;
                7'd14: glyph = dg(pnl_bcd[19:16]); 7'd15: glyph = dg(pnl_bcd[15:12]);
                7'd16: glyph = dg(pnl_bcd[11:8]);  7'd17: glyph = dg(pnl_bcd[7:4]);
                7'd18: glyph = dg(pnl_bcd[3:0]);
                7'd20: glyph = G_F; 7'd21: glyph = G_I; 7'd22: glyph = G_L; 7'd23: glyph = G_L; 7'd24: glyph = G_S;
                7'd26: glyph = dg(fc_bcd[15:12]); 7'd27: glyph = dg(fc_bcd[11:8]);
                7'd28: glyph = dg(fc_bcd[7:4]);   7'd29: glyph = dg(fc_bcd[3:0]);
                7'd31: glyph = f_has_fill ? G_L : G_SP;  7'd32: glyph = f_has_fill ? G_A : G_SP;
                7'd33: glyph = f_has_fill ? G_S : G_SP;  7'd34: glyph = f_has_fill ? G_T : G_SP;
                7'd36: glyph = !f_has_fill ? G_SP : f_fill_side ? G_S : G_B;
                7'd37: glyph = !f_has_fill ? G_SP : f_fill_side ? G_E : G_U;
                7'd38: glyph = !f_has_fill ? G_SP : f_fill_side ? G_L : G_Y;
                7'd39: glyph = (f_has_fill && f_fill_side) ? G_L : G_SP;
                7'd41: glyph = f_has_fill ? dg(fq_bcd[11:8]) : G_SP;
                7'd42: glyph = f_has_fill ? dg(fq_bcd[7:4])  : G_SP;
                7'd43: glyph = f_has_fill ? dg(fq_bcd[3:0])  : G_SP;
                7'd45: glyph = f_has_fill ? G_A : G_SP;  7'd46: glyph = f_has_fill ? G_T : G_SP;
                7'd48: glyph = f_has_fill ? dg(fp_bcd[7:4]) : G_SP;
                7'd49: glyph = f_has_fill ? dg(fp_bcd[3:0]) : G_SP;
                default: glyph = G_SP;
            endcase
            // KEYS c f dddd  RISK OK   or   RISK KILL SIDE SIZE LONG SHORT CROSS (only the flags set)
            3'd3: case (slot)
                7'd0: glyph = G_K;  7'd1: glyph = G_E;  7'd2: glyph = G_Y;  7'd3: glyph = G_S;
                7'd5:  glyph = seg_glyph(f_keys[29:25]);
                7'd7:  glyph = seg_glyph(f_keys[24:20]);
                7'd9:  glyph = seg_glyph(f_keys[19:15]);
                7'd10: glyph = seg_glyph(f_keys[14:10]);
                7'd11: glyph = seg_glyph(f_keys[9:5]);
                7'd12: glyph = seg_glyph(f_keys[4:0]);
                7'd15: glyph = G_R; 7'd16: glyph = G_I; 7'd17: glyph = G_S; 7'd18: glyph = G_K;
                7'd20: glyph = (f_reject == 6'd0) ? G_O : f_reject[0] ? G_K : G_SP;
                7'd21: glyph = (f_reject == 6'd0) ? G_K : f_reject[0] ? G_I : G_SP;
                7'd22: glyph = f_reject[0] ? G_L : G_SP;
                7'd23: glyph = f_reject[0] ? G_L : G_SP;
                7'd25: glyph = f_reject[1] ? G_S : G_SP;  7'd26: glyph = f_reject[1] ? G_I : G_SP;
                7'd27: glyph = f_reject[1] ? G_D : G_SP;  7'd28: glyph = f_reject[1] ? G_E : G_SP;
                7'd30: glyph = f_reject[2] ? G_S : G_SP;  7'd31: glyph = f_reject[2] ? G_I : G_SP;
                7'd32: glyph = f_reject[2] ? G_Z : G_SP;  7'd33: glyph = f_reject[2] ? G_E : G_SP;
                7'd35: glyph = f_reject[3] ? G_L : G_SP;  7'd36: glyph = f_reject[3] ? G_O : G_SP;
                7'd37: glyph = f_reject[3] ? G_N : G_SP;  7'd38: glyph = f_reject[3] ? G_G : G_SP;
                7'd40: glyph = f_reject[4] ? G_S : G_SP;  7'd41: glyph = f_reject[4] ? G_H : G_SP;
                7'd42: glyph = f_reject[4] ? G_O : G_SP;  7'd43: glyph = f_reject[4] ? G_R : G_SP;
                7'd44: glyph = f_reject[4] ? G_T : G_SP;
                7'd46: glyph = f_reject[5] ? G_C : G_SP;  7'd47: glyph = f_reject[5] ? G_R : G_SP;
                7'd48: glyph = f_reject[5] ? G_O : G_SP;  7'd49: glyph = f_reject[5] ? G_S : G_SP;
                7'd50: glyph = f_reject[5] ? G_S : G_SP;
                default: glyph = G_SP;
            endcase
            default: glyph = G_SP;
        endcase
    end

    // cursor readout: BID pp QTY qqqq / ASK pp QTY qqqq / --- pp QTY 0000
    always @* begin
        case (slot)
            7'd0: rglyph = d_is_bid ? G_B : d_is_ask ? G_A : G_MINUS;
            7'd1: rglyph = d_is_bid ? G_I : d_is_ask ? G_S : G_MINUS;
            7'd2: rglyph = d_is_bid ? G_D : d_is_ask ? G_K : G_MINUS;
            7'd4: rglyph = d_cur_on ? dg(cl_bcd[7:4]) : G_MINUS;
            7'd5: rglyph = d_cur_on ? dg(cl_bcd[3:0]) : G_MINUS;
            7'd7: rglyph = G_Q;  7'd8: rglyph = G_T;  7'd9: rglyph = G_Y;
            7'd11: rglyph = d_cur_on ? dg(cq_bcd[15:12]) : 6'd0;
            7'd12: rglyph = d_cur_on ? dg(cq_bcd[11:8])  : 6'd0;
            7'd13: rglyph = d_cur_on ? dg(cq_bcd[7:4])   : 6'd0;
            7'd14: rglyph = d_cur_on ? dg(cq_bcd[3:0])   : 6'd0;
            default: rglyph = G_SP;
        endcase
    end

    font_rom u_font (.glyph(in_text ? glyph : rglyph), .row(font_row(grow)), .bits(font_bits));

    wire       glyph_lit = row_ok && (gcol < GLYPH_W) && font_bits[GLYPH_W - 1 - gcol[2:0]];
    reg  [2:0] line_colour;
    always @* begin
        case (tline)
            3'd0:    line_colour = WHITE;
            3'd1:    line_colour = YELLOW;                                   // our quotes = yellow marks
            3'd2:    line_colour = (slot < 7'd9) ? WHITE : (slot < 7'd20) ? (f_pnl_neg ? RED : GREEN) : CYAN;
            default: line_colour = (slot < 7'd15) ? (keys_err ? RED : WHITE)
                                 : (f_reject == 6'd0) ? GREEN : RED;
        endcase
    end
    wire [2:0] read_colour = d_is_bid ? GREEN : d_is_ask ? RED : WHITE;
    wire       in_box      = (x >= BOX_X) && (y <= BOX_LAST_Y);
    wire       on_cursor   = f_cur_on && (level == f_cursor);

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
            colour = glyph_lit ? line_colour : BLACK;
        else if (in_box)
            colour = glyph_lit ? read_colour : BLACK;
        else if (dy != GAP_ROW) begin
            if (x < CENTRE && (CENTRE - x) <= bid_len)          colour = on_cursor ? WHITE : GREEN;
            if (x >= CENTRE && (x - CENTRE) < ask_len)          colour = on_cursor ? WHITE : RED;
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
            f_book_bid <= 1'b0; f_book_ask <= 1'b0; f_skew <= 1'b0; f_has_fill <= 1'b0;
            f_fill_side <= 1'b0; f_keys <= {6{5'd10}}; f_reject <= 6'd0; f_size <= 4'd0;
            f_cursor <= 6'd0; cap_level <= 6'd0; cap_bid <= 13'd0; cap_ask <= 13'd0;
            d_is_bid <= 1'b0; d_is_ask <= 1'b0; f_cur_on <= 1'b0; d_cur_on <= 1'b0;
        end else begin
            case (state)
                S_ADDR_BID: begin
                    if (frame_start) begin
                        f_bid_live <= our_bid_live; f_bid_px <= our_bid_px;
                        f_ask_live <= our_ask_live; f_ask_px <= our_ask_px;
                        f_pos_neg  <= position[9];  f_pnl_neg <= pnl[23];
                        f_book_bid <= bid_valid;    f_book_ask <= ask_valid;
                        f_skew     <= skew_on;      f_has_fill <= (fill_count != 16'd0);
                        f_fill_side <= fill_side;   f_keys    <= entry_disp;
                        f_reject   <= reject;
                        f_size     <= (our_size > 8'd9) ? 4'd9 : our_size[3:0];
                        f_cursor   <= cursor;
                        f_cur_on   <= cursor_active;
                        d_cur_on   <= f_cur_on;
                        d_is_bid   <= f_cur_on && (cap_bid != 13'd0);
                        d_is_ask   <= f_cur_on && (cap_bid == 13'd0) && (cap_ask != 13'd0);
                    end
                    state <= S_ADDR_ASK;
                end
                S_ADDR_ASK: begin                  // q_qty = bid qty (address from last cycle)
                    bid_len <= bar_len(q_qty);
                    if (level == f_cursor) begin cap_bid <= q_qty; cap_level <= level; end
                    state   <= S_LATCH_ASK;
                end
                S_LATCH_ASK: begin                 // q_qty = ask qty
                    ask_len <= bar_len(q_qty);
                    if (level == f_cursor) cap_ask <= q_qty;
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
