// hft_top.v  (Pierce, using Parth's market-side modules)
// Board top: ROM -> feed handler -> order book -> strategy -> risk gate, with the
// P&L tracker feeding position back to the strategy (skew) and the risk gate (limits).
// The live book, our quotes, position and P&L are on VGA (dashboard), risk status on the LEDs.
//
// vga_adapter is the course-provided VGA core (vga_adapter.v, vga_controller.v,
// vga_address_translator.v, vga_pll.v), used unmodified, with a black 320x240
// 3-bit background (black_320x240_3.mif).
//
// Controls
//   KEY[0]   reset
//   KEY[1]   step: one market message per press (when SW[1:0] = 00)
//   KEY[2]   HEX view: bot -> market -> bid depth -> ask depth -> bot ...
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
    output       VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK
);
    localparam BASE_MAX_POS = 9'd4;
    localparam DIGIT_DASH   = 4'd10, DIGIT_BLANK = 4'd15;

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
    wire [12:0] msg_qty, q_qty, trade_qty;
    wire [10:0] msg_count;
    wire        bid_valid, ask_valid, trade_valid, trade_side;
    wire [63:0] bid_mask, ask_mask;
    wire [2:0]  feed_state, book_state;
    wire        q_side;
    wire [5:0]  q_level;
    reg  [1:0]  view = 2'd0;                           // 0 bot, 1 market, 2 bid depth, 3 ask depth
    wire        depth_side  = (view == 2'd3);          // 0 = bid, 1 = ask
    wire [5:0]  depth_level = depth_side ? best_ask : best_bid;
    wire [12:0] depth_qty;

    feed_handler u_feed (
        .clk(clk), .resetn(resetn), .go(go),
        .rom_addr(rom_addr), .rom_q(rom_q),
        .msg_valid(msg_valid), .msg_type(msg_type), .msg_side(msg_side), .msg_price(msg_price),
        .msg_id(msg_id), .msg_qty(msg_qty),
        .book_ready(book_ready), .book_done(book_done),
        .msg_start(msg_start), .feed_end(feed_end), .msg_count(msg_count), .state_out(feed_state)
    );

    order_book u_book (
        .clk(clk), .resetn(resetn),
        .in_valid(msg_valid), .in_ready(book_ready),
        .in_type(msg_type), .in_side(msg_side), .in_price(msg_price), .in_id(msg_id), .in_qty(msg_qty),
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

    // Fills come from the matching engine (Parth). It is not connected yet, so
    // nothing fills and position / P&L stay 0; this is the interface it drives.
    wire       fill_valid = 1'b0;
    wire       fill_side  = 1'b0;   // 0 = our bid hit (bought), 1 = our ask lifted (sold)
    wire [5:0] fill_px    = 6'd0;
    wire [7:0] fill_qty   = 8'd0;

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

    wire [7:0] bid_dec = our_bid_live ? to_decimal(our_bid_px) : {DIGIT_DASH, DIGIT_DASH};
    wire [7:0] ask_dec = our_ask_live ? to_decimal(our_ask_px) : {DIGIT_DASH, DIGIT_DASH};

    // ---------------- Parth's views: market and depth (KEY[2] cycles) ----------------
    always @(posedge clk) if (view_press) view <= view + 2'd1;   // not reset: view survives KEY[0]

    // market view: the order book's best bid / ask and the message count
    wire [7:0] mkt_bid_dec = bid_valid ? to_decimal(best_bid) : {DIGIT_DASH, DIGIT_DASH};
    wire [7:0] mkt_ask_dec = ask_valid ? to_decimal(best_ask) : {DIGIT_DASH, DIGIT_DASH};
    wire [6:0] cnt_mod     = msg_count % 11'd100;
    wire [3:0] cnt_tens    = cnt_mod / 7'd10;
    wire [3:0] cnt_ones    = cnt_mod % 7'd10;

    // depth views: total shares waiting at the best bid / best ask (read port 2)
    wire [7:0]  dep_px_dec = depth_side ? mkt_ask_dec : mkt_bid_dec;
    wire [3:0]  qty_th = depth_qty / 13'd1000;
    wire [3:0]  qty_hu = (depth_qty / 13'd100) % 13'd10;
    wire [3:0]  qty_te = (depth_qty / 13'd10)  % 13'd10;
    wire [3:0]  qty_on = depth_qty % 13'd10;

    reg [7:0] d54, d32, d10;
    always @* begin
        case (view)
            2'd0: begin d54 = bid_dec;     d32 = ask_dec;          d10 = {DIGIT_BLANK, DIGIT_BLANK}; end
            2'd1: begin d54 = mkt_bid_dec; d32 = mkt_ask_dec;      d10 = {cnt_tens, cnt_ones};       end
            default: begin d54 = dep_px_dec; d32 = {qty_th, qty_hu}; d10 = {qty_te, qty_on};         end
        endcase
    end

    seg7 h5 (.d(d54[7:4]), .seg(HEX5));
    seg7 h4 (.d(d54[3:0]), .seg(HEX4));
    seg7 h3 (.d(d32[7:4]), .seg(HEX3));
    seg7 h2 (.d(d32[3:0]), .seg(HEX2));
    seg7 h1 (.d(d10[7:4]), .seg(HEX1));
    seg7 h0 (.d(d10[3:0]), .seg(HEX0));

    assign LEDR[9]   = killed;
    assign LEDR[8]   = feed_end;
    assign LEDR[7]   = our_ask_live;
    assign LEDR[6]   = our_bid_live;
    assign LEDR[5:0] = reject;
endmodule