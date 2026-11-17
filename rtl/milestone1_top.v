// milestone1_top.v  (Parth) - board demo for Milestone 1
// ROM -> feed handler -> order book, with the result on the HEX displays.
//
// Controls
//   KEY[0]  reset (hold briefly). Clears the book and restarts the feed.
//   KEY[1]  step: process ONE message per press
//   SW[9]   auto-play: process 4 messages per second
//   SW[8]   data: 0 = short hand-checkable test (13 msgs), 1 = market data (1000 msgs)
//           (press KEY[0] after changing it)
//   SW[7]   display: 0 = market view, 1 = level view
//   SW[6]   level view side: 0 = BID, 1 = ASK
//   SW[5:0] level view price level (0..63)
//
// Displays
//   market view : HEX5-4 best bid | HEX3-2 best ask | HEX1-0 messages processed (last 2 digits)
//                 "--" means that side of the book is empty
//   level view  : HEX5-4 selected level | HEX3-0 total quantity at that level
//
// LEDs
//   LEDR[9] bids present     LEDR[8] asks present     LEDR[7] feed finished (END reached)
//   LEDR[6] book busy        LEDR[5] last msg was a TRADE
//   LEDR[4] last msg side (on = ASK)   LEDR[3:2] last msg type (00 add, 01 cancel, 10 trade)
//   LEDR[0] auto-play on
module milestone1_top #(
    parameter AUTO_DIV   = 12_500_000,          // cycles between auto-play steps (0.25 s at 50 MHz)
    parameter MARKET_HEX = "../mem/market_data.hex",   // relative to the Quartus project folder
    parameter SMALL_HEX  = "../mem/test_small.hex"
) (
    input        CLOCK_50,
    input  [3:0] KEY,
    input  [9:0] SW,
    output [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    output [9:0] LEDR
);
    wire clk    = CLOCK_50;
    wire resetn = KEY[0];

    // ---------------- step button: synchronise + rising-edge detect ----------------
    reg [2:0] key1_sync;
    always @(posedge clk) key1_sync <= {key1_sync[1:0], ~KEY[1]};   // 1 = pressed
    wire step_pulse = key1_sync[1] & ~key1_sync[2];

    // ---------------- auto-play rate divider ----------------
    reg [24:0] div;
    reg        auto_tick;
    always @(posedge clk) begin
        if (!resetn || !SW[9]) begin
            div <= 0; auto_tick <= 1'b0;
        end else if (div == AUTO_DIV - 1) begin
            div <= 0; auto_tick <= 1'b1;
        end else begin
            div <= div + 1'b1; auto_tick <= 1'b0;
        end
    end

    wire go = step_pulse | auto_tick;

    // ---------------- ROMs (both on chip, SW[8] picks one) ----------------
    wire [9:0]  rom_addr;
    wire [31:0] market_q, small_q;
    market_rom #(.DEPTH(1024), .ADDR_W(10), .INIT_FILE(MARKET_HEX))
        u_market (.clk(clk), .addr(rom_addr),      .q(market_q));
    market_rom #(.DEPTH(16),   .ADDR_W(4),  .INIT_FILE(SMALL_HEX))
        u_small  (.clk(clk), .addr(rom_addr[3:0]), .q(small_q));

    // Only switch data source at reset so the feed never mixes the two
    reg use_market;
    always @(posedge clk) if (!resetn) use_market <= SW[8];
    wire [31:0] rom_q = use_market ? market_q
                      : ((rom_addr < 10'd16) ? small_q : 32'hFFFFFFFF);

    // ---------------- feed handler + order book ----------------
    wire        msg_valid, msg_side, book_ready, book_done, msg_start, feed_end;
    wire [1:0]  msg_type;
    wire [5:0]  msg_price, best_bid, best_ask, trade_price;
    wire [9:0]  msg_id;
    wire [12:0] msg_qty, q_qty, trade_qty;
    wire [10:0] msg_count;
    wire        bid_valid, ask_valid, trade_valid, trade_side;
    wire [63:0] bid_mask, ask_mask;
    wire [2:0]  feed_state, book_state;

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
        .q_side(SW[6]), .q_level(SW[5:0]), .q_qty(q_qty),
        .state_out(book_state)
    );

    // ---------------- remember the last message for the LEDs ----------------
    reg [1:0] last_type;
    reg       last_side;
    always @(posedge clk) begin
        if (!resetn) begin
            last_type <= 2'b00; last_side <= 1'b0;
        end else if (msg_start) begin
            last_type <= msg_type; last_side <= msg_side;
        end
    end

    // ---------------- decimal digits ----------------
    wire [3:0] bid_t = best_bid / 10,  bid_o = best_bid % 10;
    wire [3:0] ask_t = best_ask / 10,  ask_o = best_ask % 10;
    wire [6:0] cnt_mod = msg_count % 100;
    wire [3:0] cnt_t = cnt_mod / 10,   cnt_o = cnt_mod % 10;
    wire [3:0] lvl_t = SW[5:0] / 10,   lvl_o = SW[5:0] % 10;
    wire [3:0] q_th  = q_qty / 1000;
    wire [3:0] q_hu  = (q_qty / 100) % 10;
    wire [3:0] q_te  = (q_qty / 10) % 10;
    wire [3:0] q_on  = q_qty % 10;

    localparam DASH = 4'd10;

    wire level_view = SW[7];
    wire [3:0] d5 = level_view ? lvl_t : (bid_valid ? bid_t : DASH);
    wire [3:0] d4 = level_view ? lvl_o : (bid_valid ? bid_o : DASH);
    wire [3:0] d3 = level_view ? q_th  : (ask_valid ? ask_t : DASH);
    wire [3:0] d2 = level_view ? q_hu  : (ask_valid ? ask_o : DASH);
    wire [3:0] d1 = level_view ? q_te  : cnt_t;
    wire [3:0] d0 = level_view ? q_on  : cnt_o;

    seg7 h5 (.d(d5), .seg(HEX5));
    seg7 h4 (.d(d4), .seg(HEX4));
    seg7 h3 (.d(d3), .seg(HEX3));
    seg7 h2 (.d(d2), .seg(HEX2));
    seg7 h1 (.d(d1), .seg(HEX1));
    seg7 h0 (.d(d0), .seg(HEX0));

    assign LEDR[9]   = bid_valid;
    assign LEDR[8]   = ask_valid;
    assign LEDR[7]   = feed_end;
    assign LEDR[6]   = ~book_ready;
    assign LEDR[5]   = (last_type == 2'b10);
    assign LEDR[4]   = last_side;
    assign LEDR[3:2] = last_type;
    assign LEDR[1]   = 1'b0;
    assign LEDR[0]   = SW[9];
endmodule
