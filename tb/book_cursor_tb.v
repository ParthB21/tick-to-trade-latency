// book_cursor_tb.v  (Pierce, M2)
// Directed checks of the arrow-key cursor: off after reset, the first arrow starts from the
// middle, bar-to-bar jumps both ways, stopping at the last bar and at the top/bottom level,
// best bid/ask jumps, empty sides, other keys ignored.
// Run from sim/:  sh run_all.sh   (or iverilog by hand, see run_all.sh)
`timescale 1ns/1ps
module book_cursor_tb;
    localparam K_DIGIT = 5'd7, K_BUY = 5'd10, K_UP = 5'd18, K_DOWN = 5'd19, K_LEFT = 5'd20, K_RIGHT = 5'd21;

    reg clk = 0;
    always #10 clk = ~clk;
    reg         resetn = 0, key_valid = 0;
    reg  [4:0]  key_code = 0;
    reg  [63:0] bid_mask = 0, ask_mask = 0;
    reg  [5:0]  best_bid = 0, best_ask = 0;
    reg         bid_valid = 0, ask_valid = 0;
    wire [5:0]  cursor;
    wire        active;

    book_cursor dut (
        .clk(clk), .resetn(resetn), .key_valid(key_valid), .key_code(key_code),
        .bid_mask(bid_mask), .ask_mask(ask_mask),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .cursor(cursor), .active(active)
    );

    integer errors = 0, checks = 0;

    task press(input [4:0] code, input [5:0] expect, input exp_active, input [8*48-1:0] what);
        begin
            @(negedge clk); key_valid = 1; key_code = code;
            @(negedge clk); key_valid = 0;
            checks = checks + 1;
            if (cursor !== expect || active !== exp_active) begin
                errors = errors + 1;
                $display("FAIL  %0s: cursor %0d active %0d, expected %0d active %0d",
                         what, cursor, active, expect, exp_active);
            end else
                $display("PASS  %0s: cursor %0d active %0d", what, cursor, active);
        end
    endtask

    task check_reset(input [8*24-1:0] what);
        begin
            checks = checks + 1;
            if (cursor !== 6'd32 || active !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL  %0s: cursor %0d active %0d, expected 32 off", what, cursor, active);
            end else
                $display("PASS  %0s: cursor 32, off", what);
        end
    endtask

    // bids at 10, 20, 28; asks at 33, 40, 63
    task book_a;
        begin
            bid_mask = (64'd1 << 10) | (64'd1 << 20) | (64'd1 << 28);
            ask_mask = (64'd1 << 33) | (64'd1 << 40) | (64'd1 << 63);
            best_bid = 6'd28; bid_valid = 1; best_ask = 6'd33; ask_valid = 1;
        end
    endtask

    initial begin
        book_a;
        repeat (2) @(posedge clk);
        resetn = 1;
        @(negedge clk);
        check_reset("reset");

        press(K_DIGIT, 6'd32, 0, "digit key leaves the cursor off");
        bid_mask = 0; ask_mask = 0; bid_valid = 0; ask_valid = 0;
        press(K_UP,    6'd32, 0, "empty book: first up stays off");
        press(K_LEFT,  6'd32, 0, "empty book: first left stays off");
        book_a;
        press(K_UP,    6'd33, 1, "first up starts from 32 -> 33, cursor on");
        press(K_UP,    6'd40, 1, "up -> 40 (skips empty levels)");
        press(K_UP,    6'd63, 1, "up -> 63 (top level has a bar)");
        press(K_UP,    6'd63, 1, "up at the top level stays");
        press(K_DOWN,  6'd40, 1, "down -> 40");
        press(K_DOWN,  6'd33, 1, "down -> 33");
        press(K_DOWN,  6'd28, 1, "down crosses the spread to the bid at 28");
        press(K_DOWN,  6'd20, 1, "down -> 20");
        press(K_DOWN,  6'd10, 1, "down -> 10");
        press(K_DOWN,  6'd10, 1, "down below the last bar stays");
        press(K_RIGHT, 6'd33, 1, "right -> best ask 33");
        press(K_LEFT,  6'd28, 1, "left -> best bid 28");
        press(K_DIGIT, 6'd28, 1, "digit key ignored");
        press(K_BUY,   6'd28, 1, "B key ignored");

        // a bar at level 0: down must reach it, and up from 0 must work
        bid_mask = 64'd1;  best_bid = 6'd0;
        press(K_DOWN,  6'd0,  1, "down -> level 0");
        press(K_UP,    6'd33, 1, "up from 0 -> 33 (only asks above)");

        // empty book: nothing moves, the cursor stays on
        bid_mask = 0; ask_mask = 0; bid_valid = 0; ask_valid = 0;
        press(K_UP,    6'd33, 1, "empty book: up stays");
        press(K_DOWN,  6'd33, 1, "empty book: down stays");
        press(K_LEFT,  6'd33, 1, "no bids: left stays");
        press(K_RIGHT, 6'd33, 1, "no asks: right stays");

        // reset turns it off at the middle again; the first down then starts from 32
        resetn = 0; @(negedge clk); resetn = 1; @(negedge clk);
        check_reset("reset again");
        book_a;
        press(K_DOWN,  6'd28, 1, "first down starts from 32 -> 28, cursor on");

        if (errors == 0) $display("PASS book_cursor: %0d checks", checks);
        else             $display("FAIL book_cursor: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
