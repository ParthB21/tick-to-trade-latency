// strategy_tb.v  (Pierce)
// Drives every vector from python/gen_vectors.py through strategy.v and checks
// the quote against the Python model. Prices are only compared when ok = 1.
// Also checks the 2-cycle trigger -> quote_valid latency.
// Vectors cover inventory skew: position and skew_k, including the +-511/-512 extremes.
`timescale 1ns/1ps
module strategy_tb;
    parameter IN_FILE  = "vectors/strategy_in.hex";
    parameter EXP_FILE = "vectors/strategy_exp.hex";
    parameter MAX_VEC  = 1024;
    localparam LATENCY = 2;

    reg clk = 0;
    always #10 clk = ~clk;
    reg resetn = 0;

    reg        trigger = 0;
    reg  [5:0] best_bid, best_ask;
    reg        bid_valid, ask_valid;
    reg  [1:0] half_spread;
    reg  [7:0] size;
    reg signed [9:0] position;
    reg  [2:0] skew_k;
    wire       quote_valid, quote_ok;
    wire [5:0] quote_bid_px, quote_ask_px;
    wire [7:0] quote_size;

    strategy dut (
        .clk(clk), .resetn(resetn), .trigger(trigger),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .half_spread(half_spread), .size(size), .position(position), .skew_k(skew_k),
        .quote_valid(quote_valid), .quote_ok(quote_ok),
        .quote_bid_px(quote_bid_px), .quote_ask_px(quote_ask_px), .quote_size(quote_size)
    );

    reg [36:0] vin  [0:MAX_VEC-1];
    reg [20:0] vexp [0:MAX_VEC-1];
    integer i, n, errors, cycles;
    reg     e_ok;
    reg [5:0] e_bid, e_ask;
    reg [7:0] e_size;

    initial begin
        for (i = 0; i < MAX_VEC; i = i + 1) vin[i] = {37{1'bx}};
        $readmemh(IN_FILE, vin);
        $readmemh(EXP_FILE, vexp);
        n = 0;
        while (n < MAX_VEC && vin[n] !== {37{1'bx}}) n = n + 1;

        errors = 0;
        repeat (2) @(posedge clk);
        resetn = 1;

        for (i = 0; i < n; i = i + 1) begin
            @(negedge clk);
            {bid_valid, ask_valid, best_bid, best_ask, half_spread, size, position, skew_k} = vin[i];
            trigger = 1;
            @(negedge clk);
            trigger = 0;
            // scramble the inputs: the FSM must use its snapshot, not the live inputs
            {bid_valid, ask_valid, best_bid, best_ask, half_spread, size, position, skew_k} = ~vin[i];
            cycles = 1;
            while (!quote_valid) begin @(negedge clk); cycles = cycles + 1; end

            {e_ok, e_bid, e_ask, e_size} = vexp[i];
            if (cycles != LATENCY) begin
                errors = errors + 1;
                $display("LATENCY i=%0d: %0d cycles, expected %0d", i, cycles, LATENCY);
            end
            if (quote_ok !== e_ok || quote_size !== e_size ||
                (e_ok && (quote_bid_px !== e_bid || quote_ask_px !== e_ask))) begin
                errors = errors + 1;
                $display("MISMATCH i=%0d in: bid=%0d(v%0d) ask=%0d(v%0d) hs=%0d size=%0d pos=%0d k=%0d | got ok=%0d %0d/%0d size %0d | exp ok=%0d %0d/%0d size %0d",
                         i, vin[i][34:29], vin[i][36], vin[i][28:23], vin[i][35], vin[i][22:21], vin[i][20:13],
                         $signed(vin[i][12:3]), vin[i][2:0],
                         quote_ok, quote_bid_px, quote_ask_px, quote_size, e_ok, e_bid, e_ask, e_size);
            end
        end

        if (errors == 0) $display("PASS strategy: %0d vectors", n);
        else             $display("FAIL strategy: %0d errors in %0d vectors", errors, n);
        $finish;
    end
endmodule
