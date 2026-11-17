// order_book_tb.v  (Parth)
// Directed, self-checking test of the order book on its own.
// Sends a short hand-checkable sequence and, after each message, checks
// best bid, best ask and the quantity at the level that changed.
// Every check prints PASS or FAIL; the final line summarises.
`timescale 1ns/1ps
module order_book_tb;
    reg clk = 0;
    always #10 clk = ~clk;                 // 50 MHz

    reg         resetn = 0;
    reg         in_valid = 0;
    reg  [1:0]  in_type = 0;
    reg         in_side = 0;
    reg  [5:0]  in_price = 0;
    reg  [9:0]  in_id = 0;
    reg  [12:0] in_qty = 0;
    wire        in_ready, done;
    wire [5:0]  best_bid, best_ask;
    wire        bid_valid, ask_valid;
    wire [63:0] bid_mask, ask_mask;
    wire        trade_valid, trade_side;
    wire [5:0]  trade_price;
    wire [12:0] trade_qty;
    reg         q_side = 0;
    reg  [5:0]  q_level = 0;
    wire [12:0] q_qty;
    wire [2:0]  state_out;

    order_book dut (
        .clk(clk), .resetn(resetn),
        .in_valid(in_valid), .in_ready(in_ready),
        .in_type(in_type), .in_side(in_side), .in_price(in_price), .in_id(in_id), .in_qty(in_qty),
        .done(done),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .bid_mask(bid_mask), .ask_mask(ask_mask),
        .trade_valid(trade_valid), .trade_side(trade_side), .trade_price(trade_price), .trade_qty(trade_qty),
        .q_side(q_side), .q_level(q_level), .q_qty(q_qty),
        .state_out(state_out)
    );

    localparam ADD = 2'b00, CANCEL = 2'b01, TRADE = 2'b10;
    localparam BID = 1'b0,  ASK = 1'b1;
    localparam NONE = -1;

    integer pass = 0, fail = 0;
    integer saw_trade;
    integer cycles = 0;

    // Send one message and wait for the book to finish it
    task send(input [1:0] t, input s, input [5:0] p, input [9:0] id, input [12:0] q);
        begin
            @(negedge clk);
            in_type = t; in_side = s; in_price = p; in_id = id; in_qty = q; in_valid = 1;
            wait (in_ready);
            @(posedge clk); #1 in_valid = 0;
            saw_trade = 0; cycles = 1;
            while (!done) begin
                @(posedge clk); #1 cycles = cycles + 1;
                if (trade_valid) saw_trade = 1;
            end
            if (trade_valid) saw_trade = 1;
        end
    endtask

    // Check top of book
    task check_top(input integer exp_bid, input integer exp_ask, input [8*40-1:0] what);
        integer got_bid, got_ask;
        begin
            got_bid = bid_valid ? best_bid : -1;
            got_ask = ask_valid ? best_ask : -1;
            if (got_bid == exp_bid && got_ask == exp_ask) begin
                pass = pass + 1;
                $display("PASS  %0s : bid=%0d ask=%0d  (%0d cycles)", what, got_bid, got_ask, cycles);
            end else begin
                fail = fail + 1;
                $display("FAIL  %0s : bid=%0d ask=%0d, expected bid=%0d ask=%0d",
                         what, got_bid, got_ask, exp_bid, exp_ask);
            end
        end
    endtask

    // Check the quantity at one level through the query port
    task check_level(input s, input [5:0] p, input integer exp_q);
        begin
            @(negedge clk); q_side = s; q_level = p;
            @(posedge clk); #1;
            if (q_qty == exp_q) begin
                pass = pass + 1;
                $display("PASS      level %s %0d qty=%0d", s ? "ASK" : "BID", p, q_qty);
            end else begin
                fail = fail + 1;
                $display("FAIL      level %s %0d qty=%0d, expected %0d", s ? "ASK" : "BID", p, q_qty, exp_q);
            end
        end
    endtask

    initial begin
        $dumpfile("order_book_tb.vcd");
        $dumpvars(0, order_book_tb);

        repeat (3) @(posedge clk);
        resetn = 1;
        wait (in_ready);                           // RAM clear finished
        $display("reset + RAM clear done at %0d ns", $time);
        check_top(NONE, NONE, "empty book after reset");

        send(ADD,    BID, 10, 1, 100);  check_top(10, NONE, "add bid 100 @10");
                                         check_level(BID, 10, 100);
        send(ADD,    BID, 12, 2, 50);   check_top(12, NONE, "add bid 50 @12 (better)");
        send(ADD,    ASK, 15, 3, 70);   check_top(12, 15,   "add ask 70 @15");
        send(ADD,    ASK, 14, 4, 30);   check_top(12, 14,   "add ask 30 @14 (better)");
        send(ADD,    BID, 12, 5, 25);   check_top(12, 14,   "2nd order @12");
                                         check_level(BID, 12, 75);
        send(CANCEL, BID, 12, 2, 0);    check_top(12, 14,   "cancel id2: 25 left @12");
                                         check_level(BID, 12, 25);
        send(TRADE,  ASK, 14, 4, 10);   check_top(12, 14,   "partial trade 10 @14");
                                         check_level(ASK, 14, 20);
        if (saw_trade && trade_side == ASK && trade_price == 14 && trade_qty == 10) begin
            pass = pass + 1; $display("PASS      trade event: ASK @14 qty 10");
        end else begin
            fail = fail + 1; $display("FAIL      trade event missing or wrong");
        end
        send(TRADE,  ASK, 14, 4, 20);   check_top(12, 15,   "trade 20 @14 empties level");
                                         check_level(ASK, 14, 0);
        send(CANCEL, BID, 12, 5, 0);    check_top(10, 15,   "cancel last order @12");
        send(CANCEL, BID, 0, 99, 0);    check_top(10, 15,   "cancel unknown id: ignored");
        send(ADD,    BID, 13, 6, 40);   check_top(13, 15,   "add bid 40 @13");
        send(CANCEL, BID, 13, 6, 0);    check_top(10, 15,   "cancel id6");
        send(CANCEL, BID, 10, 1, 0);    check_top(NONE, 15, "cancel last bid");
        send(TRADE,  ASK, 0, 4, 5);     check_top(NONE, 15, "trade on deleted id: ignored");
        send(ADD,    BID, 63, 7, 1);    check_top(63, 15,   "edge: bid at top level 63");
        send(ADD,    ASK, 0, 8, 1);     check_top(63, 0,    "edge: ask at bottom level 0");

        $display("----------------------------------------");
        $display("%0d checks passed, %0d failed  =>  %0s", pass, fail, fail ? "FAIL" : "ALL PASS");
        $stop;
    end
endmodule
