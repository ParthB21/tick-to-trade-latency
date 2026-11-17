// hft_top_tb.v  (Pierce)
// End-to-end test of the Milestone 1 board top, using the simulation VGA stub.
//   1. Replays all 1000 market messages at full speed.
//   2. Logs every order the risk gate sends to out/orders.txt
//      (python/e2e.py compares it to the chained Python model).
//   3. Measures tick-to-trade: msg_start (feed latches a message) -> order_valid.
//   4. After the feed ends, waits two full VGA frames and dumps the frame buffer
//      to out/frame.hex (python/e2e.py compares it pixel by pixel).
//   5. Checks the HEX digits and the kill switch through the real synchroniser.
`timescale 1ns/1ps
module hft_top_tb;
    parameter MARKET_HEX = "../mem/market_data.hex";
    localparam MAX_SIZE = 8;
    localparam FRAMES_TO_WAIT = 2;
    localparam TIMEOUT_CYCLES = 1_000_000;
    localparam KILL_SETTLE    = 5;          // 2 sync flops + 1 register, with margin

    reg clk = 0;
    always #10 clk = ~clk;

    reg  [3:0] KEY;
    reg  [9:0] SW;
    wire [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
    wire [9:0] LEDR;
    wire [7:0] VGA_R, VGA_G, VGA_B;
    wire       VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK;

    hft_top #(.MARKET_HEX(MARKET_HEX), .MAX_SIZE(MAX_SIZE)) dut (
        .CLOCK_50(clk), .KEY(KEY), .SW(SW),
        .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
        .LEDR(LEDR), .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N), .VGA_CLK(VGA_CLK)
    );

    // expected HEX patterns, decoded with the tb's own (simulation-only) / and %
    wire [3:0] bid_tens = dut.our_bid_px / 10, bid_ones = dut.our_bid_px % 10;
    wire [3:0] ask_tens = dut.our_ask_px / 10, ask_ones = dut.our_ask_px % 10;
    wire [6:0] exp_hex5, exp_hex4, exp_hex3, exp_hex2;
    seg7 e5 (.d(bid_tens), .seg(exp_hex5));
    seg7 e4 (.d(bid_ones), .seg(exp_hex4));
    seg7 e3 (.d(ask_tens), .seg(exp_hex3));
    seg7 e2 (.d(ask_ones), .seg(exp_hex2));

    // ---------------- order log + latency ----------------
    integer fout, lat, lat_first, lat_min, lat_max, orders, cycle, frames, errors;
    reg     timing;

    always @(posedge clk) begin
        cycle = cycle + 1;
        if (dut.msg_start) begin lat = 0; timing = 1; end
        else if (timing)   lat = lat + 1;
        if (dut.order_valid && !dut.killed) begin
            $fdisplay(fout, "%0d %0d %0d %0d %0d %0d", dut.msg_count - 1,
                      dut.our_bid_live, dut.our_bid_px, dut.our_ask_live, dut.our_ask_px, dut.our_size);
            orders = orders + 1;
            timing = 0;
            if (orders == 1)        lat_first = lat;   // waits for the book's RAM clear after reset
            else if (lat < lat_min) lat_min = lat;
            if (orders > 1 && lat > lat_max) lat_max = lat;
        end
        if (dut.vga_plot && dut.vga_x == 9'd319 && dut.vga_y == 8'd191) frames = frames + 1;
        if (cycle > TIMEOUT_CYCLES) begin $display("FAIL: timeout"); $finish; end
    end

    initial begin
        fout = $fopen("out/orders.txt", "w");
        cycle = 0; orders = 0; frames = 0; errors = 0; timing = 0;
        lat = 0; lat_min = 1 << 30; lat_max = 0;

        //     kill  max_pos 8  hs 1   size 2        full speed
        SW  = {1'b0, 2'b01,     2'b01, 2'b01, 1'b0, 2'b10};
        KEY = 4'b1110;                                      // hold reset
        $fdisplay(fout, "config half_spread=%0d size=%0d max_pos=%0d max_size=%0d",
                  SW[6:5], 1 << SW[4:3], 4 << SW[8:7], MAX_SIZE);
        repeat (5) @(posedge clk);
        KEY = 4'b1111;

        wait (LEDR[8]);                                     // feed reached END
        $display("replay done: %0d orders, tick-to-trade %0d..%0d cycles (msg_start -> order_valid)",
                 orders, lat_min, lat_max);
        $display("  first message after reset: %0d cycles (includes the order book's RAM clear)", lat_first);
        frames = 0;
        wait (frames == FRAMES_TO_WAIT);
        @(posedge clk);
        $writememh("out/frame.hex", dut.VGA.fb);
        $fclose(fout);

        if ({HEX5, HEX4} !== (dut.our_bid_live ? {exp_hex5, exp_hex4} : {2{7'b0111111}}) ||
            {HEX3, HEX2} !== (dut.our_ask_live ? {exp_hex3, exp_hex2} : {2{7'b0111111}})) begin
            errors = errors + 1;
            $display("FAIL HEX: bid %b@%0d ask %b@%0d shows %b %b %b %b",
                     dut.our_bid_live, dut.our_bid_px, dut.our_ask_live, dut.our_ask_px,
                     HEX5, HEX4, HEX3, HEX2);
        end

        SW[9] = 1'b1;                                       // kill
        repeat (KILL_SETTLE) @(posedge clk);
        if (LEDR[9] !== 1'b1 || LEDR[7:6] !== 2'b00 || LEDR[0] !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL kill: LEDR = %b", LEDR);
        end
        SW[9] = 1'b0;                                       // must stay killed
        repeat (KILL_SETTLE) @(posedge clk);
        if (LEDR[9] !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL kill latch: released when the switch went down");
        end

        if (errors == 0) $display("PASS hft_top: HEX and kill switch checks");
        else             $display("FAIL hft_top: %0d errors", errors);
        $finish;
    end
endmodule
