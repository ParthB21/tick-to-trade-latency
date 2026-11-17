// milestone1_top_tb.v  (Parth)
// Simulates the exact board top level: presses KEY[1] once per message on the
// short test data and reads the HEX displays back as digits, so you can see
// in simulation what the TA will see on the board.
`timescale 1ns/1ps
module milestone1_top_tb;
    reg        CLOCK_50 = 0;
    always #10 CLOCK_50 = ~CLOCK_50;

    reg  [3:0] KEY = 4'b1110;               // KEY[0] held = reset, others released
    reg  [9:0] SW  = 10'd0;                 // small test data, market view, no auto-play
    wire [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
    wire [9:0] LEDR;

    milestone1_top #(
        .AUTO_DIV(50),
        .MARKET_HEX("../mem/market_data.hex"),
        .SMALL_HEX("../mem/test_small.hex")
    ) dut (
        .CLOCK_50(CLOCK_50), .KEY(KEY), .SW(SW),
        .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
        .LEDR(LEDR)
    );

    // turn a 7-segment pattern back into a character for printing
    function [7:0] ch(input [6:0] s);
        case (s)
            7'b1000000: ch = "0"; 7'b1111001: ch = "1"; 7'b0100100: ch = "2";
            7'b0110000: ch = "3"; 7'b0011001: ch = "4"; 7'b0010010: ch = "5";
            7'b0000010: ch = "6"; 7'b1111000: ch = "7"; 7'b0000000: ch = "8";
            7'b0010000: ch = "9"; 7'b0111111: ch = "-"; default:    ch = " ";
        endcase
    endfunction

    task show(input [8*12-1:0] label);
        $display("%0s HEX: [%s%s %s%s %s%s]  LEDR=%b",
                 label, ch(HEX5), ch(HEX4), ch(HEX3), ch(HEX2), ch(HEX1), ch(HEX0), LEDR);
    endtask

    task press_step;
        begin
            KEY[1] = 0; repeat (5) @(posedge CLOCK_50);
            KEY[1] = 1; repeat (20) @(posedge CLOCK_50);
        end
    endtask

    integer i;
    initial begin
        $dumpfile("milestone1_top_tb.vcd");
        $dumpvars(0, milestone1_top_tb);
        repeat (5) @(posedge CLOCK_50);
        KEY[0] = 1;                              // release reset
        repeat (1100) @(posedge CLOCK_50);       // wait for the RAM clear
        $display("                 bid ask cnt");
        show("after reset ");
        for (i = 1; i <= 14; i = i + 1) begin
            press_step;
            $write("step %2d      ", i); show("");
        end

        SW[7] = 1; SW[6] = 0; SW[5:0] = 6'd15;   // level view: BID 15 (empty)
        repeat (3) @(posedge CLOCK_50); show("BID lvl 15  ");
        SW[6] = 1;                               // ASK 15 should hold 70
        repeat (3) @(posedge CLOCK_50); show("ASK lvl 15  ");
        SW[7] = 0;

        // auto-play the market data
        SW[8] = 1; KEY[0] = 0; repeat (3) @(posedge CLOCK_50); KEY[0] = 1;
        repeat (1100) @(posedge CLOCK_50);
        SW[9] = 1;
        repeat (60 * 50) @(posedge CLOCK_50);
        show("auto 60 msgs");
        $finish;
    end
endmodule
