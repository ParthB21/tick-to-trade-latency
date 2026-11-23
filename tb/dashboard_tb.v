// dashboard_tb.v  (Pierce)
// Runs dashboard.v against a fake order book and the simulation VGA stub, for
// several quote / position / P&L cases (negative, clamped, zero, -512).
// For each case it waits two full frames, dumps the frame buffer to
// out/dash_<n>.hex and logs the case to out/dash_cases.txt;
// python/check_dashboard.py renders the same cases and compares every pixel.
`timescale 1ns/1ps
module dashboard_tb;
    localparam N_CASES        = 3;
    localparam FRAMES_TO_WAIT = 2;          // the first may have started before the inputs changed
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
    wire [8:0] x;
    wire [7:0] y;
    wire [2:0] colour;
    wire       plot;

    dashboard dut (
        .clk(clk), .resetn(resetn),
        .q_side(q_side), .q_level(q_level), .q_qty(q_qty),
        .our_bid_live(bid_live), .our_bid_px(bid_px), .our_ask_live(ask_live), .our_ask_px(ask_px),
        .position(position), .pnl(pnl),
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
            $fdisplay(fcase, "%0d %0d %0d %0d %0d %0d %0d", n, b_live, b_px, a_live, a_px, pos, p);
        end
    endtask

    initial begin
        fcase = $fopen("out/dash_cases.txt", "w");
        bid_live = 0; ask_live = 0; bid_px = 0; ask_px = 0; position = 0; pnl = 0;
        repeat (2) @(posedge clk);
        resetn = 1;
        //       n  bid      ask      position  pnl
        run_case(0, 1, 6'd30, 1, 6'd34, -10'sd37,  -24'sd123456);   // negative, |P&L| clamps to 99999
        run_case(1, 0, 6'd0,  1, 6'd63,  10'sd5,    24'sd4321);     // bid pulled, ask at the top level
        run_case(2, 1, 6'd0,  0, 6'd0,  -10'sd512,  24'sd0);        // -512 magnitude, zero P&L is "+"
        $fclose(fcase);
        $display("dashboard: %0d cases dumped", N_CASES);
        $finish;
    end
endmodule
