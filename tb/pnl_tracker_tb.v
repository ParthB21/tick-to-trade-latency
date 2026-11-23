// pnl_tracker_tb.v  (Pierce)
// Applies one vector per clock edge (reset, fill, book top) and compares
// position and P&L against python/pnl.py. Also reports the most long and most
// short positions reached, so a vector set that never goes short cannot pass silently.
`timescale 1ns/1ps
module pnl_tracker_tb;
    parameter IN_FILE  = "vectors/pnl_in.hex";
    parameter EXP_FILE = "vectors/pnl_exp.hex";
    parameter MAX_VEC  = 1024;
    localparam signed [9:0] MIN_EXTREME = 10'sd500;   // the vectors reach +-510

    reg clk = 0;
    always #10 clk = ~clk;

    reg        rst, fill_valid, fill_side, bid_valid, ask_valid;
    reg  [5:0] fill_px, best_bid, best_ask;
    reg  [7:0] fill_qty;
    wire signed [9:0]  position;
    wire signed [23:0] pnl;

    pnl_tracker dut (
        .clk(clk), .resetn(~rst),
        .fill_valid(fill_valid), .fill_side(fill_side), .fill_px(fill_px), .fill_qty(fill_qty),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .position(position), .pnl(pnl)
    );

    reg [30:0] vin  [0:MAX_VEC-1];
    reg [33:0] vexp [0:MAX_VEC-1];
    integer i, n, errors;
    reg signed [9:0] pos_hi, pos_lo;

    initial begin
        for (i = 0; i < MAX_VEC; i = i + 1) vin[i] = {31{1'bx}};
        $readmemh(IN_FILE, vin);
        $readmemh(EXP_FILE, vexp);
        n = 0;
        while (n < MAX_VEC && vin[n] !== {31{1'bx}}) n = n + 1;

        @(negedge clk);
        rst = 1; fill_valid = 0;
        @(negedge clk);

        errors = 0; pos_hi = 0; pos_lo = 0;
        for (i = 0; i < n; i = i + 1) begin
            {rst, fill_valid, fill_side, fill_px, fill_qty, best_bid, bid_valid, best_ask, ask_valid} = vin[i];
            @(negedge clk);                       // one posedge applied the vector
            if (position > pos_hi) pos_hi = position;
            if (position < pos_lo) pos_lo = position;
            if ({position, pnl} !== vexp[i]) begin
                errors = errors + 1;
                $display("MISMATCH i=%0d fill v=%b side=%b %0d@%0d | got pos=%0d pnl=%0d | exp pos=%0d pnl=%0d",
                         i, fill_valid, fill_side, fill_qty, fill_px, position, pnl,
                         $signed(vexp[i][33:24]), $signed(vexp[i][23:0]));
            end
        end

        if (pos_hi < MIN_EXTREME || pos_lo > -MIN_EXTREME) begin
            errors = errors + 1;
            $display("COVERAGE: position range %0d..%0d, expected beyond +-%0d", pos_lo, pos_hi, MIN_EXTREME);
        end
        if (errors == 0) $display("PASS pnl_tracker: %0d cycles, position %0d..%0d", n, pos_lo, pos_hi);
        else             $display("FAIL pnl_tracker: %0d errors in %0d cycles", errors, n);
        $finish;
    end
endmodule
