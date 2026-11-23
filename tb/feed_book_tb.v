// feed_book_tb.v  (Parth)
// System test: ROM -> feed handler -> order book, running at full speed.
// After every message it writes "index best_bid best_ask" to OUT_FILE
// (-1 = that side is empty). python/compare.py checks this file against the
// Python reference model.
//
// Change MEM_FILE / OUT_FILE to run the small test:
//   ModelSim:  vsim -gMEM_FILE=../mem/test_small.hex -gOUT_FILE=sim_out_small.txt work.feed_book_tb
`timescale 1ns/1ps
module feed_book_tb;
    parameter MEM_FILE = "../mem/market_data.hex";
    parameter OUT_FILE = "sim_out.txt";

    reg clk = 0;
    always #10 clk = ~clk;                 // 50 MHz
    reg resetn = 0;

    wire [9:0]  rom_addr;
    wire [31:0] rom_q;
    wire        msg_valid, msg_side, book_ready, book_done, msg_start, feed_end;
    wire [1:0]  msg_type;
    wire [5:0]  msg_price, best_bid, best_ask;
    wire [9:0]  msg_id;
    wire [12:0] msg_qty, q_qty, trade_qty;
    wire [10:0] msg_count;
    wire        bid_valid, ask_valid, trade_valid, trade_side;
    wire [5:0]  trade_price;
    wire [63:0] bid_mask, ask_mask;
    wire [2:0]  feed_state, book_state;

    market_rom #(.INIT_FILE(MEM_FILE)) u_rom (.clk(clk), .addr(rom_addr), .q(rom_q));

    feed_handler u_feed (
        .clk(clk), .resetn(resetn), .go(1'b1),
        .rom_addr(rom_addr), .rom_q(rom_q),
        .msg_valid(msg_valid), .msg_type(msg_type), .msg_side(msg_side), .msg_price(msg_price),
        .msg_id(msg_id), .msg_qty(msg_qty),
        .book_ready(book_ready), .book_done(book_done),
        .msg_start(msg_start), .feed_end(feed_end), .msg_count(msg_count), .state_out(feed_state)
    );

    order_book u_book (
        .clk(clk), .resetn(resetn),
        .in_valid(msg_valid), .in_ready(book_ready),
        .in_type(msg_type), .in_side(msg_side), .in_price(msg_price), .in_id({1'b0, msg_id}), .in_qty(msg_qty),
        .done(book_done),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .bid_mask(bid_mask), .ask_mask(ask_mask),
        .trade_valid(trade_valid), .trade_side(trade_side), .trade_price(trade_price), .trade_qty(trade_qty),
        .q_side(1'b0), .q_level(6'd0), .q_qty(q_qty),
        .state_out(book_state)
    );

    integer fout, n = 0, trades = 0;
    integer t_first, t_last;
    integer bid_out, ask_out;

    always @(posedge clk) begin
        if (resetn && book_done) begin
            bid_out = bid_valid ? best_bid : -1;
            ask_out = ask_valid ? best_ask : -1;
            $fdisplay(fout, "%0d %0d %0d", n, bid_out, ask_out);
            if (n == 0) t_first = $time;
            t_last = $time;
            n = n + 1;
        end
        if (trade_valid) trades = trades + 1;
    end

    initial begin
        $dumpfile("feed_book_tb.vcd");
        $dumpvars(0, feed_book_tb);
        fout = $fopen(OUT_FILE, "w");
        repeat (3) @(posedge clk);
        resetn = 1;
        wait (feed_end);
        repeat (2) @(posedge clk);
        $fclose(fout);
        $display("processed %0d messages (%0d trades) from %0s", n, trades, MEM_FILE);
        if (n > 1)
            $display("throughput: %0d ns for %0d messages = %0d cycles per message",
                     t_last - t_first, n - 1, (t_last - t_first) / 20 / (n - 1));
        $display("results written to %0s", OUT_FILE);
        $stop;
    end

    initial begin
        #5_000_000;                            // safety timeout
        $display("TIMEOUT"); $stop;
    end
endmodule
