// risk_gate_tb.v  (Pierce)
// Applies one vector per clock edge (reset, kill switch, quote, book top,
// position, limits) and compares every output against python/risk.py.
// Also reports which reject flags were exercised, so a vector set that
// never trips a check cannot pass silently.
`timescale 1ns/1ps
module risk_gate_tb;
    parameter IN_FILE  = "vectors/risk_in.hex";
    parameter EXP_FILE = "vectors/risk_exp.hex";
    parameter MAX_VEC  = 1024;

    reg clk = 0;
    always #10 clk = ~clk;

    reg              rst, kill_sw, quote_valid, quote_ok, bid_valid, ask_valid;
    reg       [5:0]  quote_bid_px, quote_ask_px, best_bid, best_ask;
    reg       [7:0]  quote_size, max_size;
    reg signed [9:0] position;
    reg       [8:0]  max_pos;

    wire       order_valid, our_bid_live, our_ask_live, killed;
    wire [5:0] our_bid_px, our_ask_px, reject;
    wire [7:0] our_size;

    risk_gate dut (
        .clk(clk), .resetn(~rst), .kill_sw(kill_sw),
        .quote_valid(quote_valid), .quote_ok(quote_ok),
        .quote_bid_px(quote_bid_px), .quote_ask_px(quote_ask_px), .quote_size(quote_size),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .position(position), .max_pos(max_pos), .max_size(max_size),
        .order_valid(order_valid), .our_bid_live(our_bid_live), .our_bid_px(our_bid_px),
        .our_ask_live(our_ask_live), .our_ask_px(our_ask_px), .our_size(our_size),
        .killed(killed), .reject(reject)
    );

    reg [64:0] vin  [0:MAX_VEC-1];
    reg [29:0] vexp [0:MAX_VEC-1];
    wire [29:0] got = {order_valid, our_bid_live, our_bid_px, our_ask_live, our_ask_px,
                       our_size, killed, reject};
    integer i, n, errors;
    reg [5:0] seen;

    initial begin
        for (i = 0; i < MAX_VEC; i = i + 1) vin[i] = {65{1'bx}};
        $readmemh(IN_FILE, vin);
        $readmemh(EXP_FILE, vexp);
        n = 0;
        while (n < MAX_VEC && vin[n] !== {65{1'bx}}) n = n + 1;

        // start from reset
        @(negedge clk);
        rst = 1; kill_sw = 0; quote_valid = 0;
        @(negedge clk);

        errors = 0; seen = 0;
        for (i = 0; i < n; i = i + 1) begin
            {rst, kill_sw, quote_valid, quote_ok, quote_bid_px, quote_ask_px, quote_size,
             best_bid, bid_valid, best_ask, ask_valid, position, max_pos, max_size} = vin[i];
            @(negedge clk);                       // one posedge applied the vector
            seen = seen | reject;
            if (got !== vexp[i]) begin
                errors = errors + 1;
                $display("MISMATCH i=%0d pos=%0d max_pos=%0d | got  ov=%b bid %b@%0d ask %b@%0d sz=%0d killed=%b rej=%b",
                         i, position, max_pos, order_valid, our_bid_live, our_bid_px,
                         our_ask_live, our_ask_px, our_size, killed, reject);
                $display("                                    | exp  ov=%b bid %b@%0d ask %b@%0d sz=%0d killed=%b rej=%b",
                         vexp[i][29], vexp[i][28], vexp[i][27:22], vexp[i][21], vexp[i][20:15],
                         vexp[i][14:7], vexp[i][6], vexp[i][5:0]);
            end
        end

        if (seen != 6'b111111) begin
            errors = errors + 1;
            $display("COVERAGE: reject flags exercised = %b, expected all six", seen);
        end
        if (errors == 0) $display("PASS risk_gate: %0d cycles, all 6 reject flags exercised", n);
        else             $display("FAIL risk_gate: %0d errors in %0d cycles", errors, n);
        $finish;
    end
endmodule
