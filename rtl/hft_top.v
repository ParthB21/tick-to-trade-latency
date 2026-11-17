// hft_top.v  (Pierce, using Parth's market-side modules)
// Milestone 1 board top: ROM -> feed handler -> order book -> strategy -> risk gate,
// with the live book and our quotes on VGA (dashboard) and risk status on the LEDs.
//
// vga_adapter is the course-provided VGA core (vga_adapter.v, vga_controller.v,
// vga_address_translator.v, vga_pll.v + black.mif), used unmodified.
//
// Controls
//   KEY[0]   reset
//   KEY[1]   step: one market message per press (when SW[1:0] = 00)
//   SW[1:0]  replay: 00 step with KEY[1], 01 auto 4 msgs/s, 1x full speed
//   SW[4:3]  quote size per side: 1 / 2 / 4 / 8
//   SW[6:5]  half-spread: 0..3 ticks either side of the mid
//   SW[8:7]  max |position|: 4 / 8 / 16 / 32
//   SW[9]    kill switch (latches until reset)
// Displays
//   HEX5-4 our bid price, HEX3-2 our ask price ("--" = that side not live)
//   LEDR[9] killed   LEDR[8] feed finished   LEDR[7] ask live   LEDR[6] bid live
//   LEDR[5:0] sticky reject flags: 5 cross, 4 short limit, 3 long limit,
//             2 size, 1 quote not ok (book one-sided), 0 kill
module hft_top #(
    parameter AUTO_DIV   = 12_500_000,               // 0.25 s at 50 MHz
    parameter MARKET_HEX = "../mem/market_data.hex", // relative to the Quartus project folder
    parameter MAX_SIZE   = 8
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
    wire resetn = key_s[0];

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
    wire [31:0] rom_q;
    market_rom #(.DEPTH(1024), .ADDR_W(10), .INIT_FILE(MARKET_HEX))
        u_rom (.clk(clk), .addr(rom_addr), .q(rom_q));

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
        .state_out(book_state)
    );

    // ---------------- trading side (Pierce) ----------------
    wire       quote_valid, quote_ok;
    wire [5:0] quote_bid_px, quote_ask_px;
    wire [7:0] quote_size;
    wire [7:0] size    = 8'd1 << sw[4:3];
    wire [8:0] max_pos = BASE_MAX_POS << sw[8:7];

    strategy u_strategy (
        .clk(clk), .resetn(resetn), .trigger(book_done),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .half_spread(sw[6:5]), .size(size),
        .quote_valid(quote_valid), .quote_ok(quote_ok),
        .quote_bid_px(quote_bid_px), .quote_ask_px(quote_ask_px), .quote_size(quote_size)
    );

    // Flat until the matching engine and P&L tracker produce fills (M2).
    wire signed [9:0] position = 10'sd0;

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
        .x(vga_x), .y(vga_y), .colour(vga_colour), .plot(vga_plot)
    );

    vga_adapter #(
        .RESOLUTION("320x240"), .MONOCHROME("FALSE"),
        .BITS_PER_COLOUR_CHANNEL(1), .BACKGROUND_IMAGE("black.mif")
    ) VGA (
        .resetn(resetn), .clock(clk),
        .colour(vga_colour), .x(vga_x), .y(vga_y), .plot(vga_plot),
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

    seg7 h5 (.d(bid_dec[7:4]), .seg(HEX5));
    seg7 h4 (.d(bid_dec[3:0]), .seg(HEX4));
    seg7 h3 (.d(ask_dec[7:4]), .seg(HEX3));
    seg7 h2 (.d(ask_dec[3:0]), .seg(HEX2));
    seg7 h1 (.d(DIGIT_BLANK),  .seg(HEX1));
    seg7 h0 (.d(DIGIT_BLANK),  .seg(HEX0));

    assign LEDR[9]   = killed;
    assign LEDR[8]   = feed_end;
    assign LEDR[7]   = our_ask_live;
    assign LEDR[6]   = our_bid_live;
    assign LEDR[5:0] = reject;
endmodule
