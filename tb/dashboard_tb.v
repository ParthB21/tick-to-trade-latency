// dashboard_tb.v  (Pierce)
// Runs dashboard.v against a fake order book and the simulation VGA stub, for
// several quote / position / P&L / cursor cases (negative, clamped, zero, -512).
// For each case it waits three full frames, dumps the frame buffer to
// out/dash_<n>.hex and logs the case to out/dash_cases.txt;
// python/check_dashboard.py renders the same cases and compares every pixel.
`timescale 1ns/1ps
module dashboard_tb;
    localparam N_CASES        = 3;
    // the first may have started before the inputs changed, and the cursor readout shows the
    // shares captured on the frame before, so frame 3 is the first fully new one
    localparam FRAMES_TO_WAIT = 3;
    localparam LAST_X = 9'd319, LAST_Y = 8'd239;

    reg clk = 0;
    always #10 clk = ~clk;
    reg resetn = 0;

    // fake book read port, 1-cycle latency like order_book; same formula as check_dashboard.py
    wire        q_side;
    wire [5:0]  q_level;
    reg  [12:0] q_qty;
    always @(posedge clk)
        q_qty <= ((q_level + q_side) % 5 == 0) ? 13'd0 : (q_level * 97 + q_side * 1234) % 3000;

    reg               bid_live, ask_live;
    reg        [5:0]  bid_px, ask_px;
    reg signed [9:0]  position;
    reg signed [23:0] pnl;
    // status panel inputs (M2)
    reg        [5:0]  best_bid, best_ask;
    reg               bid_valid, ask_valid, skew_on, fill_side;
    reg        [10:0] msg_count;
    reg        [7:0]  our_size, fill_qty;
    reg        [15:0] fill_count;
    reg        [5:0]  fill_px, reject;
    reg        [29:0] entry_disp;
    reg        [5:0]  cursor;
    reg               cursor_active;
    wire [8:0] x;
    wire [7:0] y;
    wire [2:0] colour;
    wire       plot;

    dashboard dut (
        .clk(clk), .resetn(resetn),
        .q_side(q_side), .q_level(q_level), .q_qty(q_qty),
        .our_bid_live(bid_live), .our_bid_px(bid_px), .our_ask_live(ask_live), .our_ask_px(ask_px),
        .position(position), .pnl(pnl),
        .best_bid(best_bid), .bid_valid(bid_valid), .best_ask(best_ask), .ask_valid(ask_valid),
        .msg_count(msg_count), .our_size(our_size), .skew_on(skew_on),
        .fill_count(fill_count), .fill_side(fill_side), .fill_px(fill_px), .fill_qty(fill_qty),
        .entry_disp(entry_disp), .reject(reject), .cursor(cursor), .cursor_active(cursor_active),
        .x(x), .y(y), .colour(colour), .plot(plot)
    );

    wire [7:0] vga_r, vga_g, vga_b;
    wire       vga_hs, vga_vs, vga_blank_n, vga_sync_n, vga_clk;
    vga_adapter #(.RESOLUTION("320x240"), .COLOR_DEPTH(3)) VGA (
        .resetn(resetn), .clock(clk), .color(colour), .x(x), .y(y), .write(plot),
        .VGA_R(vga_r), .VGA_G(vga_g), .VGA_B(vga_b), .VGA_HS(vga_hs), .VGA_VS(vga_vs),
        .VGA_BLANK_N(vga_blank_n), .VGA_SYNC_N(vga_sync_n), .VGA_CLK(vga_clk)
    );

    integer frames = 0;
    always @(posedge clk) if (plot && x == LAST_X && y == LAST_Y) frames = frames + 1;

    integer fcase, c;
    reg [8*32-1:0] name;

    task run_case(input integer n, input b_live, input [5:0] b_px, input a_live, input [5:0] a_px,
                  input signed [9:0] pos, input signed [23:0] p);
        begin
            @(negedge clk);
            bid_live = b_live; bid_px = b_px; ask_live = a_live; ask_px = a_px;
            position = pos; pnl = p;
            frames = 0;
            wait (frames == FRAMES_TO_WAIT);
            @(posedge clk);
            $sformat(name, "out/dash_%0d.hex", n);
            $writememh(name, VGA.fb);
            $fdisplay(fcase, "%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                      n, b_live, b_px, a_live, a_px, pos, p,
                      best_bid, bid_valid, best_ask, ask_valid, msg_count, our_size, skew_on,
                      fill_count, fill_side, fill_px, fill_qty, reject,
                      entry_disp[29:25], entry_disp[24:20], entry_disp[19:15],
                      entry_disp[14:10], entry_disp[9:5], entry_disp[4:0], cursor, cursor_active);
        end
    endtask

    initial begin
        fcase = $fopen("out/dash_cases.txt", "w");
        bid_live = 0; ask_live = 0; bid_px = 0; ask_px = 0; position = 0; pnl = 0;
        best_bid = 0; best_ask = 0; bid_valid = 0; ask_valid = 0; skew_on = 0; fill_side = 0;
        msg_count = 0; our_size = 0; fill_qty = 0; fill_count = 0; fill_px = 0; reject = 0;
        entry_disp = {6{5'd10}}; cursor = 6'd32; cursor_active = 0;
        repeat (2) @(posedge clk);
        resetn = 1;
        //       n  bid      ask      position  pnl
        // panel case 0: two-sided book, skew on, no fills yet, keyboard idle, no rejects
        best_bid = 6'd30; bid_valid = 1; best_ask = 6'd34; ask_valid = 1; msg_count = 11'd1234;
        our_size = 8'd2; skew_on = 1; fill_count = 0; reject = 6'd0; entry_disp = {6{5'd10}};
        cursor = 6'd30; cursor_active = 1;                 // ask-only level: red readout
        run_case(0, 1, 6'd30, 1, 6'd34, -10'sd37,  -24'sd123456);   // negative, |P&L| clamps to 99999
        // panel case 1: no bids, a sell fill, typing "S P 14", KILL + SIDE + CROSS flags
        best_bid = 6'd0; bid_valid = 0; best_ask = 6'd63; ask_valid = 1; msg_count = 11'd7;
        our_size = 8'd8; skew_on = 0; fill_count = 16'd12; fill_side = 1; fill_px = 6'd63; fill_qty = 8'd3;
        reject = 6'b100011; entry_disp = {5'd17, 5'd23, 5'd15, 5'd15, 5'd1, 5'd4};
        cursor = 6'd63; cursor_active = 1;                 // top level: white bar runs under the readout box
        run_case(1, 0, 6'd0,  1, 6'd63,  10'sd5,    24'sd4321);     // bid pulled, ask at the top level
        // panel case 2: clamps (2047 msgs, size 255 -> 9, 12345 fills -> 9999), a buy fill, "Err", all flags
        best_bid = 6'd0; bid_valid = 1; best_ask = 6'd1; ask_valid = 1; msg_count = 11'd2047;
        our_size = 8'd255; fill_count = 16'd12345; fill_side = 0; fill_px = 6'd0; fill_qty = 8'd255;
        reject = 6'b111111; entry_disp = {5'd20, 5'd21, 5'd21, 5'd15, 5'd15, 5'd15};
        cursor = 6'd2; cursor_active = 0;                           // off: no white bar, "--- -- QTY 0000"
        run_case(2, 1, 6'd0,  0, 6'd0,  -10'sd512,  24'sd0);        // -512 magnitude, zero P&L is "+"
        $fclose(fcase);
        $display("dashboard: %0d cases dumped", N_CASES);
        $finish;
    end
endmodule
