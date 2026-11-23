// hft_system_tb.v  (Parth, M2)
// System test of the real board top (hft_top), checked against python/system_model.py.
//
// The ROM is stepped one message at a time with KEY[1] (SW[1:0] = 00), exactly as on the
// board. After the n-th ROM message, the keyboard lines the script schedules "after n"
// are typed on the PS/2 pins as real serial frames (bytes from sim/vectors/sys_kb.hex,
// made by system_model.py --kb-hex from sim/kb_script.txt).
//
// For every message the order book processes (ROM or keyboard) it writes one line to
// OUT_FILE, read from hft_top's internal signals:
//   seq src idx best_bid best_ask bid_live bid_px ask_live ask_px fside fpx fqty position cash
// (same columns as the model; position/cash are "na" until Pierce's P&L tracker is in
//  hft_top: define HAS_PNL and set the two signal names below when it is).
// Then:  python ../python/sys_compare.py sys_expected.txt sys_out.txt
//
// Switches: SW[6:5] = HS (half-spread, parameter), size 2, max position 8, kill off.
`timescale 1ns/1ps
module hft_system_tb;
    parameter MARKET_HEX = "../mem/market_data.hex";
    parameter KB_HEX     = "vectors/sys_kb.hex";
    parameter OUT_FILE   = "sys_out.txt";
    parameter HS         = 1;
    parameter PS2_HALF   = 2000;                  // ns; a real keyboard is 30-50 us

    reg clk = 0;
    always #10 clk = ~clk;

    reg  [3:0] KEY = 4'b1111;
    reg  [9:0] SW;
    reg        ps2_clk = 1, ps2_dat = 1;
    wire [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
    wire [9:0] LEDR;
    wire [7:0] VGA_R, VGA_G, VGA_B;
    wire       VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK;

    hft_top #(.MARKET_HEX(MARKET_HEX)) dut (
        .CLOCK_50(clk), .KEY(KEY), .SW(SW),
        .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
        .LEDR(LEDR), .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N), .VGA_CLK(VGA_CLK),
        .PS2_CLK(ps2_clk), .PS2_DAT(ps2_dat)
    );

    // ---------------- per-message log, from internal signals ----------------
    integer fout, seq = 0, kb_rows = 0, fills = 0, keyboard_msgs = 0;
    reg     src;
    integer idx, fside, fpx, fqty, bb, ba;

    always @(posedge clk) begin
        if (dut.book_done) begin                  // message applied; which source was it?
            src = dut.arb_owner;
            idx = src ? kb_rows : dut.msg_count;  // feed msg_count counts up in this same edge
            fside = -1; fpx = -1; fqty = 0;
        end
        if (dut.fill_valid) begin                 // done + 1
            fside = dut.fill_side; fpx = dut.fill_px; fqty = dut.fill_qty;
            fills = fills + 1;
        end
        if (dut.order_valid && !dut.killed) begin // done + 3: the risk gate's new quotes
            bb = dut.bid_valid ? dut.best_bid : -1;
            ba = dut.ask_valid ? dut.best_ask : -1;
`ifdef HAS_PNL
            $fdisplay(fout, "%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d", seq, src, idx, bb, ba,
                      dut.our_bid_live, dut.our_bid_px, dut.our_ask_live, dut.our_ask_px,
                      fside, fpx, fqty, dut.position, dut.cash);
`else
            $fdisplay(fout, "%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d na na", seq, src, idx, bb, ba,
                      dut.our_bid_live, dut.our_bid_px, dut.our_ask_live, dut.our_ask_px,
                      fside, fpx, fqty);
`endif
            seq = seq + 1;
            if (src) begin kb_rows = kb_rows + 1; keyboard_msgs = keyboard_msgs + 1; end
        end
    end

    // ---------------- PS/2 keyboard model ----------------
    task ps2_send(input [7:0] b);
        integer k;
        reg [10:0] fr;
        begin
            fr = {1'b1, ~^b, b, 1'b0};             // stop, odd parity, data LSB first, start
            for (k = 0; k < 11; k = k + 1) begin
                ps2_dat = fr[k];
                #(PS2_HALF) ps2_clk = 0;
                #(PS2_HALF) ps2_clk = 1;
            end
            ps2_dat = 1;
            #(PS2_HALF * 4);
        end
    endtask

    reg [31:0] kb [0:4095];
    integer kp = 0, n = 0, typed_lines = 0;

    task type_scheduled(input integer done_n);     // every byte scheduled "after done_n" or earlier
        begin
            if (kb[kp] !== 32'hFFFFFFFF && kb[kp][31:16] <= done_n) begin
                while (kb[kp] !== 32'hFFFFFFFF && kb[kp][31:16] <= done_n) begin
                    ps2_send(kb[kp][7:0]);
                    kp = kp + 1;
                end
                repeat (40) @(posedge clk);       // let a keyboard message go all the way through
            end
        end
    endtask

    task step;                                     // one KEY[1] press, then wait for the message
        begin
            @(negedge clk) KEY[1] = 0;
            repeat (4) @(posedge clk);
            @(negedge clk) KEY[1] = 1;
            repeat (40) @(posedge clk);            // 8-9 cycles per message + 4 to the new quote
        end
    endtask

    initial begin
        $readmemh(KB_HEX, kb);
        fout = $fopen(OUT_FILE, "w");
        //     kill max_pos 8  hs        size 2  -     step mode
        SW = {1'b0, 2'b01, HS[1:0], 2'b01, 1'b0, 2'b00};
        KEY[0] = 0;
        repeat (5) @(posedge clk);
        KEY[0] = 1;
        wait (dut.book_ready);                     // order book RAM clear done
        $display("reset done at %0d ns; stepping the ROM, typing %0s", $time, KB_HEX);

        type_scheduled(0);
        while (!dut.feed_end) begin
            step;
            n = dut.msg_count;
            type_scheduled(n);
        end
        type_scheduled(1 << 20);                   // anything scheduled after the END
        repeat (20) @(posedge clk);
        $fclose(fout);
        $display("done at %0d ns: %0d messages logged (%0d ROM + %0d keyboard), %0d fills, %0d keyboard entries rejected",
                 $time, seq, seq - keyboard_msgs, keyboard_msgs, fills, dut.kb_errs);
        $display("now run:  python ../python/sys_compare.py sys_expected.txt %0s", OUT_FILE);
        $stop;
    end

    initial begin #500_000_000; $display("TIMEOUT"); $stop; end
endmodule
