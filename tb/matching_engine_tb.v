// matching_engine_tb.v  (Parth, M2)
// Part 1: named, hand-checkable cases (at / through / behind our price, partial
//         fills, running out of size, side not live, wrong side, kill).
// Part 2: 500 random events from python/gen_match_vectors.py, every output checked
//         against python/matching.py the cycle after each event.
// Run from sim/:  do run_matching_engine.do
`timescale 1ns/1ps
module matching_engine_tb;
    reg clk = 0;
    always #10 clk = ~clk;

    reg         resetn = 0;
    reg         trade_valid = 0, trade_side = 0;
    reg  [5:0]  trade_price = 0;
    reg  [12:0] trade_qty = 0;
    reg         order_valid = 0, our_bid_live = 0, our_ask_live = 0;
    reg  [5:0]  our_bid_px = 0, our_ask_px = 0;
    reg  [7:0]  our_size = 0;
    wire        fill_valid, fill_side;
    wire [5:0]  fill_px;
    wire [7:0]  fill_qty, bid_rem, ask_rem;
    wire [15:0] fill_count;

    matching_engine dut (
        .clk(clk), .resetn(resetn),
        .trade_valid(trade_valid), .trade_side(trade_side), .trade_price(trade_price), .trade_qty(trade_qty),
        .order_valid(order_valid), .our_bid_live(our_bid_live), .our_bid_px(our_bid_px),
        .our_ask_live(our_ask_live), .our_ask_px(our_ask_px), .our_size(our_size),
        .fill_valid(fill_valid), .fill_side(fill_side), .fill_px(fill_px), .fill_qty(fill_qty),
        .fill_count(fill_count), .bid_rem(bid_rem), .ask_rem(ask_rem)
    );

    localparam BID = 1'b0, ASK = 1'b1;
    integer pass = 0, fail = 0;

    // risk gate sends a quote: one order_valid pulse, the prices then stay put
    task quote(input bl, input [5:0] bp, input al, input [5:0] ap, input [7:0] sz);
        begin
            @(negedge clk);
            our_bid_live = bl; our_bid_px = bp; our_ask_live = al; our_ask_px = ap; our_size = sz;
            order_valid = 1;
            @(negedge clk) order_valid = 0;
        end
    endtask

    // book reports a trade, then check the fill the cycle after
    task trade_check(input s, input [5:0] p, input [12:0] q,
                     input exp_fill, input exp_side, input [5:0] exp_px, input [7:0] exp_qty,
                     input [8*44-1:0] what);
        begin
            @(negedge clk);
            trade_valid = 1; trade_side = s; trade_price = p; trade_qty = q;
            @(negedge clk) trade_valid = 0;                // fill_valid is high now
            if (fill_valid === exp_fill &&
                (!exp_fill || (fill_side === exp_side && fill_px === exp_px && fill_qty === exp_qty))) begin
                pass = pass + 1;
                if (exp_fill) $display("PASS  %0s : fill %s %0d @%0d  (rem bid %0d ask %0d)", what,
                                       fill_side ? "SELL" : "BUY", fill_qty, fill_px, bid_rem, ask_rem);
                else          $display("PASS  %0s : no fill  (rem bid %0d ask %0d)", what, bid_rem, ask_rem);
            end else begin
                fail = fail + 1;
                $display("FAIL  %0s : got fill=%b side=%b px=%0d qty=%0d, expected fill=%b side=%b px=%0d qty=%0d",
                         what, fill_valid, fill_side, fill_px, fill_qty, exp_fill, exp_side, exp_px, exp_qty);
            end
        end
    endtask

    // ---------------- random vectors ----------------
    localparam N_VEC = 500;
    reg [43:0] vin  [0:N_VEC-1];
    reg [31:0] vexp [0:N_VEC-1];
    reg [31:0] got;
    integer i, vfail = 0;

    initial begin
        $readmemh("vectors/match_in.hex",  vin);
        $readmemh("vectors/match_exp.hex", vexp);

        repeat (3) @(posedge clk);
        @(negedge clk) resetn = 1;

        $display("---- named cases (t = %0d ns) ----", $time);
        quote(1, 30, 0, 0, 4);
        trade_check(BID, 30, 10,  1, 0, 30, 4, "bid 30x4, trade bid @30 (at our price)");
        trade_check(BID, 29, 10,  0, 0, 0, 0,  "same quote again: all 4 used up");
        quote(1, 30, 0, 0, 4);
        trade_check(BID, 31, 10,  0, 0, 0, 0,  "trade bid @31: above our 30 (behind)");
        trade_check(BID, 28, 1,   1, 0, 30, 1, "trade bid @28: through us, we get OUR price");
        trade_check(BID, 30, 2,   1, 0, 30, 2, "partial: 2 more at 30");
        trade_check(BID, 30, 50,  1, 0, 30, 1, "only 1 share left on the quote");
        quote(0, 0, 1, 33, 3);
        trade_check(ASK, 33, 1,   1, 1, 33, 1, "ask 33x3, trade ask @33 qty 1");
        trade_check(ASK, 34, 500, 1, 1, 33, 2, "trade ask @34: through us, last 2");
        quote(0, 0, 1, 33, 3);
        trade_check(ASK, 32, 5,   0, 0, 0, 0,  "trade ask @32: below our 33 (behind)");
        quote(0, 25, 1, 20, 8);
        trade_check(BID, 20, 5,   0, 0, 0, 0,  "bid side not live: no fill");
        trade_check(BID, 19, 5,   0, 0, 0, 0,  "bid-side trade never fills our ask");
        quote(1, 25, 1, 27, 8);
        quote(0, 25, 0, 27, 8);                                    // kill: both sides pulled
        trade_check(BID, 25, 5,   0, 0, 0, 0,  "after kill (sides not live): no fill");
        if (fill_count == 16'd6) begin pass = pass + 1; $display("PASS  fill_count = 6"); end
        else begin fail = fail + 1; $display("FAIL  fill_count = %0d, expected 6", fill_count); end
        $display("named cases: %0d passed, %0d failed (t = %0d ns)", pass, fail, $time);

        // ---- random vectors against the Python model ----
        @(negedge clk) resetn = 0;
        @(negedge clk) resetn = 1;
        our_bid_live = 0; our_bid_px = 0; our_ask_live = 0; our_ask_px = 0; our_size = 0;
        $display("---- %0d random vectors (t = %0d ns) ----", N_VEC, $time);
        for (i = 0; i < N_VEC; i = i + 1) begin
            @(negedge clk);
            {our_bid_live, our_bid_px, our_ask_live, our_ask_px, our_size} = vin[i][41:20];
            {trade_side, trade_price, trade_qty} = vin[i][19:0];
            order_valid = (vin[i][43:42] == 2'd0);
            trade_valid = (vin[i][43:42] == 2'd1);
            @(negedge clk);
            order_valid = 0; trade_valid = 0;
            got = {fill_valid, fill_valid ? {fill_side, fill_px, fill_qty} : 15'd0, bid_rem, ask_rem};
            if (got !== vexp[i]) begin
                vfail = vfail + 1;
                if (vfail <= 10) $display("FAIL vector %0d: got %h expected %h", i, got, vexp[i]);
            end
        end
        $display("random vectors: %0d / %0d match python/matching.py", N_VEC - vfail, N_VEC);

        $display("----------------------------------------");
        if (fail == 0 && vfail == 0) $display("ALL PASS: %0d named checks, %0d vectors, %0d fills total",
                                              pass, N_VEC, fill_count);
        else $display("FAIL: %0d named, %0d vectors", fail, vfail);
        $stop;
    end
endmodule
