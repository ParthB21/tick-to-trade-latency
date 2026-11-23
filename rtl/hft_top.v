// hft_top.v  (Pierce, using Parth's market-side modules)
// Board top:
//   ROM -> feed handler ---\
//                           order arbiter -> order book -> strategy -> risk gate
//   PS/2 -> order entry ---/                     |            ^          | our quotes
//                                                +-> matching engine <---+
//                                                       | fills          | position
//                                                       +-> P&L tracker -+ (also skew)
// The live book, our quotes, position and P&L are on VGA (dashboard), risk status on the LEDs.
// M2 (Parth): order arbiter, PS/2 order entry, matching engine, entry + fills HEX views,
// HEX digits through bin2bcd_comb instead of / and %.
// M2 (Pierce): P&L tracker feeding position back to the strategy (skew) and the risk gate
// (limits), position and P&L text on VGA.
//
// vga_adapter is the course-provided VGA core (vga_adapter.v, vga_controller.v,
// vga_address_translator.v, vga_pll.v), used unmodified, with a black 320x240
// 3-bit background (black_320x240_3.mif).
//
// Controls
//   KEY[0]   reset
//   KEY[1]   step: one market message per press (when SW[1:0] = 00)
//   KEY[2]   HEX view: bot -> market -> bid depth -> ask depth -> entry -> fills -> bot ...
//            (any keyboard key jumps to the entry view)
//   PS/2     order entry: B<price> <qty>Enter, S<price> <qty>Enter, X<id>Enter, T<id> <qty>Enter
//   KEY[3]   data set: 1000-message market <-> 13-message hand-checkable test
//            (switching restarts everything, like KEY[0]; starts on the market data)
//   SW[1:0]  replay: 00 step with KEY[1], 01 auto 4 msgs/s, 1x full speed
//   SW[2]    inventory skew on: quotes shift 1 tick per 4 shares held
//   SW[4:3]  quote size per side: 1 / 2 / 4 / 8
//   SW[6:5]  half-spread: 0..3 ticks either side of the mid
//   SW[8:7]  max |position|: 4 / 8 / 16 / 32
//   SW[9]    kill switch (latches until reset)
// Displays (KEY[2] cycles; starts in bot view, and the view is kept across reset)
//   bot view      : HEX5-4 our bid price, HEX3-2 our ask price ("--" = side not live), HEX1-0 blank
//   market view   : HEX5-4 market best bid, HEX3-2 market best ask ("--" = side empty),
//                   HEX1-0 messages processed (last 2 digits)
//   bid depth view: HEX5-4 best bid price, HEX3-0 total shares at the best bid
//   ask depth view: HEX5-4 best ask price, HEX3-0 total shares at the best ask
//   entry view    : what is being typed (b/S/C/t, then P price / q qty / d id, digits),
//                   "b d 0007" = sent, order ID 7;  "Err" = rejected
//   fills view    : HEX5 b (we bought) / S (we sold) for the last fill, HEX4-3 its price,
//                   HEX2-0 number of fills (last 3 digits);  "F-----" = no fills yet
//   LEDR[9] killed   LEDR[8] feed finished   LEDR[7] ask live   LEDR[6] bid live
//   LEDR[5:0] sticky reject flags: 5 cross, 4 short limit, 3 long limit,
//             2 size, 1 quote not ok (book one-sided), 0 kill
module hft_top #(
    parameter AUTO_DIV   = 12_500_000,               // 0.25 s at 50 MHz
    parameter MARKET_HEX = "../mem/market_data.hex", // relative to the Quartus project folder
    parameter SMALL_HEX  = "../mem/test_small.hex",  // 13-message hand-checkable test
    parameter MAX_SIZE   = 8,
    parameter SKEW_K     = 2                         // skew = position * SKEW_K / 8 ticks
) (
    input        CLOCK_50,
    input  [3:0] KEY,
    input  [9:0] SW,
    output [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    output [9:0] LEDR,
    output [7:0] VGA_R, VGA_G, VGA_B,
    output       VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK,
    input        PS2_CLK,                            // keyboard (receive only, never driven)
    input        PS2_DAT
);
    localparam BASE_MAX_POS = 9'd4;

    wire clk = CLOCK_50;

    // ---------------- synchronise board inputs ----------------
    wire [1:0] key_s;
    wire [9:0] sw;
    sync2 #(.WIDTH(12)) u_sync (.clk(clk), .d({KEY[1:0], SW}), .q({key_s, sw}));

    // ---------------- KEY[2] view and KEY[3] data set (Parth) ----------------
    wire [1:0] key23_s;
    sync2 #(.WIDTH(2)) u_sync_k23 (.clk(clk), .d(KEY[3:2]), .q(key23_s));
    reg  [1:0] key23_prev = 2'b11;                     // "pressed" at power-up: no false press
    always @(posedge clk) key23_prev <= ~key23_s;
    wire view_press = ~key23_s[0] & ~key23_prev[0];    // one pulse per KEY[2] press
    wire data_press = ~key23_s[1] & ~key23_prev[1];    // one pulse per KEY[3] press

    reg       use_test = 1'b0;                         // 0 = 1000-message market, 1 = 13-message test
    reg [3:0] restart  = 4'd0;                         // short internal reset after switching data
    always @(posedge clk) begin
        if (data_press) begin
            use_test <= ~use_test;
            restart  <= 4'd15;
        end else if (restart != 4'd0)
            restart <= restart - 1'b1;
    end

    wire resetn = key_s[0] & (restart == 4'd0);

    reg step_prev;
    always @(posedge clk) step_prev <= ~key_s[1];
    wire step_pulse = ~key_s[1] & ~step_prev;          // KEY is active low: press = 1 -> rising edge

    // ---------------- replay rate ----------------
    wire auto_play  = (sw[1:0] == 2'b01);
    wire full_speed = sw[1];

    reg [24:0] div;
    reg        auto_tick;
    always @(posedge clk) begin
        if (!resetn || !auto_play) begin
            div <= 25'd0; auto_tick <= 1'b0;
        end else if (div == AUTO_DIV - 1) begin
            div <= 25'd0; auto_tick <= 1'b1;
        end else begin
            div <= div + 1'b1; auto_tick <= 1'b0;
        end
    end
    wire go = full_speed | auto_tick | step_pulse;

    // ---------------- market side (Parth) ----------------
    wire [9:0]  rom_addr;
    wire [31:0] market_q, small_q;
    market_rom #(.DEPTH(1024), .ADDR_W(10), .INIT_FILE(MARKET_HEX))
        u_rom (.clk(clk), .addr(rom_addr), .q(market_q));
    market_rom #(.DEPTH(16), .ADDR_W(4), .INIT_FILE(SMALL_HEX))
        u_small (.clk(clk), .addr(rom_addr[3:0]), .q(small_q));
    wire [31:0] rom_q = use_test ? ((rom_addr < 10'd16) ? small_q : 32'hFFFFFFFF) : market_q;

    wire        msg_valid, msg_side, book_ready, book_done, msg_start, feed_end;
    wire [1:0]  msg_type;
    wire [5:0]  msg_price, best_bid, best_ask, trade_price;
    wire [9:0]  msg_id;
    wire        f_ready, f_done, k_valid, k_ready, k_done, arb_valid, arb_side, arb_owner;
    wire [31:0] k_msg;
    wire [1:0]  arb_type, arb_state;
    wire [5:0]  arb_price;
    wire [10:0] arb_id;
    wire [12:0] arb_qty;
    wire [12:0] msg_qty, q_qty, trade_qty;
    wire [10:0] msg_count;
    wire        bid_valid, ask_valid, trade_valid, trade_side;
    wire [63:0] bid_mask, ask_mask;
    wire [2:0]  feed_state, book_state;
    wire        q_side;
    wire [5:0]  q_level;
    reg  [2:0]  view = 3'd0;                           // 0 bot, 1 market, 2 bid depth, 3 ask depth,
                                                       // 4 entry, 5 fills
    wire        depth_side  = (view == 3'd3);          // 0 = bid, 1 = ask
    wire [5:0]  depth_level = depth_side ? best_ask : best_bid;
    wire [12:0] depth_qty;

    feed_handler u_feed (
        .clk(clk), .resetn(resetn), .go(go),
        .rom_addr(rom_addr), .rom_q(rom_q),
        .msg_valid(msg_valid), .msg_type(msg_type), .msg_side(msg_side), .msg_price(msg_price),
        .msg_id(msg_id), .msg_qty(msg_qty),
        .book_ready(f_ready), .book_done(f_done),        // through the arbiter (M2)
        .msg_start(msg_start), .feed_end(feed_end), .msg_count(msg_count), .state_out(feed_state)
    );

    // ---------------- keyboard order entry (Parth, M2) ----------------
    wire [7:0]  kb_byte;
    wire        kb_byte_valid, kb_frame_err, key_valid;
    wire [4:0]  key_code;
    wire [9:0]  kb_next_id;
    wire [15:0] kb_sent, kb_errs;
    wire [29:0] entry_disp;
    wire [1:0]  entry_state;

    ps2_rx u_ps2 (.clk(clk), .resetn(resetn), .ps2_clk(PS2_CLK), .ps2_dat(PS2_DAT),
                  .rx_byte(kb_byte), .rx_valid(kb_byte_valid), .frame_err(kb_frame_err));
    kb_decoder u_kbd (.clk(clk), .resetn(resetn), .rx_byte(kb_byte), .rx_valid(kb_byte_valid),
                      .key_valid(key_valid), .key_code(key_code));
    order_entry u_entry (
        .clk(clk), .resetn(resetn), .key_valid(key_valid), .key_code(key_code),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .k_valid(k_valid), .k_msg(k_msg), .k_ready(k_ready),
        .next_id(kb_next_id), .sent_count(kb_sent), .err_count(kb_errs),
        .disp(entry_disp), .state_out(entry_state)
    );

    // ---------------- order arbiter (Parth, M2): ROM feed + keyboard -> book ----------------
    order_arbiter u_arb (
        .clk(clk), .resetn(resetn),
        .f_valid(msg_valid), .f_msg({msg_type, msg_side, msg_price, msg_id, msg_qty}),
        .f_ready(f_ready), .f_done(f_done),
        .k_valid(k_valid), .k_msg(k_msg), .k_ready(k_ready), .k_done(k_done),
        .b_valid(arb_valid), .b_type(arb_type), .b_side(arb_side), .b_price(arb_price),
        .b_id(arb_id), .b_qty(arb_qty), .b_ready(book_ready), .b_done(book_done),
        .owner(arb_owner), .state_out(arb_state)
    );

    order_book u_book (
        .clk(clk), .resetn(resetn),
        .in_valid(arb_valid), .in_ready(book_ready),
        .in_type(arb_type), .in_side(arb_side), .in_price(arb_price), .in_id(arb_id), .in_qty(arb_qty),
        .done(book_done),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .bid_mask(bid_mask), .ask_mask(ask_mask),
        .trade_valid(trade_valid), .trade_side(trade_side), .trade_price(trade_price), .trade_qty(trade_qty),
        .q_side(q_side), .q_level(q_level), .q_qty(q_qty),
        .q2_side(depth_side), .q2_level(depth_level), .q2_qty(depth_qty),
        .state_out(book_state)
    );

    // ---------------- trading side (Pierce) ----------------
    wire       quote_valid, quote_ok;
    wire [5:0] quote_bid_px, quote_ask_px;
    wire [7:0] quote_size;
    wire [7:0] size    = 8'd1 << sw[4:3];
    wire [8:0] max_pos = BASE_MAX_POS << sw[8:7];
    wire [2:0] skew_k  = sw[2] ? SKEW_K[2:0] : 3'd0;
    wire signed [9:0]  position;
    wire signed [23:0] pnl;

    strategy u_strategy (
        .clk(clk), .resetn(resetn), .trigger(book_done),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .half_spread(sw[6:5]), .size(size), .position(position), .skew_k(skew_k),
        .quote_valid(quote_valid), .quote_ok(quote_ok),
        .quote_bid_px(quote_bid_px), .quote_ask_px(quote_ask_px), .quote_size(quote_size)
    );

    // Fills come from the matching engine (Parth, below).
    wire       fill_valid, fill_side;   // fill_side 0 = our bid hit (bought), 1 = our ask lifted (sold)
    wire [5:0] fill_px;
    wire [7:0] fill_qty;

    pnl_tracker u_pnl (
        .clk(clk), .resetn(resetn),
        .fill_valid(fill_valid), .fill_side(fill_side), .fill_px(fill_px), .fill_qty(fill_qty),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .position(position), .pnl(pnl)
    );

    wire       order_valid, our_bid_live, our_ask_live, killed;
    wire [5:0] our_bid_px, our_ask_px, reject;
    wire [7:0] our_size;

    risk_gate u_risk (
        .clk(clk), .resetn(resetn), .kill_sw(sw[9]),
        .quote_valid(quote_valid), .quote_ok(quote_ok),
        .quote_bid_px(quote_bid_px), .quote_ask_px(quote_ask_px), .quote_size(quote_size),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .position(position), .max_pos(max_pos), .max_size(MAX_SIZE[7:0]),
        .order_valid(order_valid), .our_bid_live(our_bid_live), .our_bid_px(our_bid_px),
        .our_ask_live(our_ask_live), .our_ask_px(our_ask_px), .our_size(our_size),
        .killed(killed), .reject(reject)
    );

    // ---------------- matching engine (Parth, M2): fills for our quotes ----------------
    wire [7:0]  bid_rem, ask_rem;           // fill_* are declared above, at the P&L tracker
    wire [15:0] fill_count;

    matching_engine u_match (
        .clk(clk), .resetn(resetn),
        .trade_valid(trade_valid), .trade_side(trade_side), .trade_price(trade_price), .trade_qty(trade_qty),
        .order_valid(order_valid), .our_bid_live(our_bid_live), .our_bid_px(our_bid_px),
        .our_ask_live(our_ask_live), .our_ask_px(our_ask_px), .our_size(our_size),
        .fill_valid(fill_valid), .fill_side(fill_side), .fill_px(fill_px), .fill_qty(fill_qty),
        .fill_count(fill_count), .bid_rem(bid_rem), .ask_rem(ask_rem)
    );

    // ---------------- VGA ----------------
    wire [8:0] vga_x;
    wire [7:0] vga_y;
    wire [2:0] vga_colour;
    wire       vga_plot;

    dashboard u_dash (
        .clk(clk), .resetn(resetn),
        .q_side(q_side), .q_level(q_level), .q_qty(q_qty),
        .our_bid_live(our_bid_live), .our_bid_px(our_bid_px),
        .our_ask_live(our_ask_live), .our_ask_px(our_ask_px),
        .position(position), .pnl(pnl),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .msg_count(msg_count), .our_size(our_size), .skew_on(sw[2]),
        .fill_count(fill_count), .fill_side(fill_side), .fill_px(fill_px), .fill_qty(fill_qty),
        .entry_disp(entry_disp), .reject(reject),
        .x(vga_x), .y(vga_y), .colour(vga_colour), .plot(vga_plot)
    );

    vga_adapter #(
        .RESOLUTION("320x240"),
        .COLOR_DEPTH(3),                          // 1 bit each for R, G, B (matches vga_colour)
        .BACKGROUND_IMAGE("black_320x240_3.mif")
    ) VGA (
        .resetn(resetn), .clock(clk),
        .color(vga_colour), .x(vga_x), .y(vga_y), .write(vga_plot),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N), .VGA_SYNC_N(VGA_SYNC_N), .VGA_CLK(VGA_CLK)
    );

    // ---------------- HEX: our quote prices in decimal ----------------
    // 0..63 to two digits with comparators (no divider)
    function [7:0] to_decimal(input [5:0] v);
        reg [3:0] tens;
        reg [5:0] ones;
        begin
            tens = (v >= 6'd60) ? 4'd6 : (v >= 6'd50) ? 4'd5 : (v >= 6'd40) ? 4'd4 :
                   (v >= 6'd30) ? 4'd3 : (v >= 6'd20) ? 4'd2 : (v >= 6'd10) ? 4'd1 : 4'd0;
            ones = v - tens * 6'd10;               // constant multiply, not a divider
            to_decimal = {tens, ones[3:0]};
        end
    endfunction

    // HEX digit codes are 5 bits (seg7.v): 0..9, 10 dash, 15 blank, 16+ letters
    localparam [4:0] C_DASH = 5'd10, C_BLANK = 5'd15, C_b = 5'd16, C_S = 5'd17, C_F = 5'd25;
    localparam [9:0] DASH2 = {C_DASH, C_DASH}, BLANK2 = {C_BLANK, C_BLANK};
    function [9:0] two(input [7:0] d); two = {1'b0, d[7:4], 1'b0, d[3:0]}; endfunction

    wire [7:0] bid_dec = to_decimal(our_bid_px);
    wire [7:0] ask_dec = to_decimal(our_ask_px);

    // ---------------- Parth's views (KEY[2] cycles; a keyboard key jumps to the entry view) ----------------
    always @(posedge clk) begin                        // not reset: view survives KEY[0]
        if (key_valid)       view <= 3'd4;
        else if (view_press) view <= (view == 3'd5) ? 3'd0 : view + 3'd1;
    end

    // market view: the order book's best bid / ask and the message count
    wire [9:0]  mkt_bid = bid_valid ? two(to_decimal(best_bid)) : DASH2;
    wire [9:0]  mkt_ask = ask_valid ? two(to_decimal(best_ask)) : DASH2;
    wire [19:0] cnt_bcd, qty_bcd, fills_bcd;
    bin2bcd_comb u_cnt   (.bin({3'd0, msg_count}), .bcd(cnt_bcd));       // shift-and-add-3, no divider
    bin2bcd_comb u_qty   (.bin({1'b0, depth_qty}), .bcd(qty_bcd));
    bin2bcd_comb u_fills (.bin(fill_count[13:0]),  .bcd(fills_bcd));

    reg [29:0] codes;                                  // HEX5..HEX0, 5 bits each
    always @* begin
        case (view)
            3'd0: codes = {our_bid_live ? two(bid_dec) : DASH2, our_ask_live ? two(ask_dec) : DASH2, BLANK2};
            3'd1: codes = {mkt_bid, mkt_ask, 1'b0, cnt_bcd[7:4], 1'b0, cnt_bcd[3:0]};
            3'd2,
            3'd3: codes = {depth_side ? mkt_ask : mkt_bid,
                           1'b0, qty_bcd[15:12], 1'b0, qty_bcd[11:8], 1'b0, qty_bcd[7:4], 1'b0, qty_bcd[3:0]};
            3'd4: codes = entry_disp;
            default: codes = (fill_count == 16'd0) ? {C_F, {5{C_DASH}}}
                           : {fill_side ? C_S : C_b, two(to_decimal(fill_px)),
                              1'b0, fills_bcd[11:8], 1'b0, fills_bcd[7:4], 1'b0, fills_bcd[3:0]};
        endcase
    end

    seg7 h5 (.d(codes[29:25]), .seg(HEX5));
    seg7 h4 (.d(codes[24:20]), .seg(HEX4));
    seg7 h3 (.d(codes[19:15]), .seg(HEX3));
    seg7 h2 (.d(codes[14:10]), .seg(HEX2));
    seg7 h1 (.d(codes[9:5]),   .seg(HEX1));
    seg7 h0 (.d(codes[4:0]),   .seg(HEX0));

    assign LEDR[9]   = killed;
    assign LEDR[8]   = feed_end;
    assign LEDR[7]   = our_ask_live;
    assign LEDR[6]   = our_bid_live;
    assign LEDR[5:0] = reject;
endmodule