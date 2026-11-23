// order_entry_tb.v  (Parth, M2)
// Keyboard path on its own: real PS/2 serial frames -> ps2_rx -> kb_decoder -> order_entry.
// The arbiter is a stand-in that accepts each message ACCEPT_DELAY cycles after k_valid
// rises (as if the book were busy), so the "hold until accepted" behaviour is tested too.
// The book top is held at best bid 30 / best ask 33 (for the crossing check).
//
// Part 1: 24 typed lines from python/gen_entry_vectors.py (every command, every reject,
//         Backspace, Esc, keypad Enter, an ignored arrow key), then one frame with a bad
//         parity bit that must be dropped. Messages are compared to python/order_entry.py.
// Part 2: named checks of the HEX display codes.
// PS/2 clock: PS2_HALF ns per half period. A real keyboard is 30-50 us; 2 us keeps the
// simulation short and the receiver does not care (it only looks for falling edges).
// Run from sim/:  do run_order_entry.do
`timescale 1ns/1ps
module order_entry_tb;
    parameter PS2_HALF = 2000;
    localparam ACCEPT_DELAY = 6;

    reg clk = 0;
    always #10 clk = ~clk;
    reg resetn = 0;

    reg ps2_clk = 1, ps2_dat = 1;
    wire [7:0] rx_byte;
    wire rx_valid, frame_err, key_valid, k_valid;
    wire [4:0] key_code;
    wire [31:0] k_msg;
    reg  k_ready = 0;
    wire [9:0] next_id;
    wire [15:0] sent_count, err_count;
    wire [29:0] disp;
    wire [1:0]  entry_state;

    ps2_rx u_rx (.clk(clk), .resetn(resetn), .ps2_clk(ps2_clk), .ps2_dat(ps2_dat),
                 .rx_byte(rx_byte), .rx_valid(rx_valid), .frame_err(frame_err));
    kb_decoder u_dec (.clk(clk), .resetn(resetn), .rx_byte(rx_byte), .rx_valid(rx_valid),
                      .key_valid(key_valid), .key_code(key_code));
    order_entry u_entry (
        .clk(clk), .resetn(resetn), .key_valid(key_valid), .key_code(key_code),
        .best_bid(6'd30), .bid_valid(1'b1), .best_ask(6'd33), .ask_valid(1'b1),
        .k_valid(k_valid), .k_msg(k_msg), .k_ready(k_ready),
        .next_id(next_id), .sent_count(sent_count), .err_count(err_count),
        .disp(disp), .state_out(entry_state)
    );

    // ---------------- PS/2 keyboard model ----------------
    // start 0, 8 data bits LSB first, odd parity, stop 1; data changes while clock is high
    task ps2_send(input [7:0] b, input bad_parity);
        integer k;
        reg [10:0] fr;
        begin
            fr = {1'b1, ~^b ^ bad_parity, b, 1'b0};
            for (k = 0; k < 11; k = k + 1) begin
                ps2_dat = fr[k];
                #(PS2_HALF) ps2_clk = 0;
                #(PS2_HALF) ps2_clk = 1;
            end
            ps2_dat = 1;
            #(PS2_HALF * 4);                    // gap between bytes
        end
    endtask

    task press(input [7:0] code);               // make, then release (F0 + make)
        begin ps2_send(code, 0); ps2_send(8'hF0, 0); ps2_send(code, 0); end
    endtask

    // ---------------- arbiter stand-in + message log ----------------
    reg [31:0] got [0:63];
    integer n_got = 0, wait_cnt = 0, frame_errs = 0;
    always @(posedge clk) begin
        k_ready <= 0;
        if (k_valid && !k_ready) begin
            if (wait_cnt == ACCEPT_DELAY) begin
                k_ready <= 1; wait_cnt = 0;
                got[n_got] = k_msg; n_got = n_got + 1;
            end else wait_cnt = wait_cnt + 1;
        end
        if (frame_err) frame_errs = frame_errs + 1;
    end

    // ---------------- display check ----------------
    integer pass = 0, fail = 0;
    task check_disp(input [29:0] exp, input [8*40-1:0] what);
        begin
            #(PS2_HALF * 2);
            if (disp === exp) begin pass = pass + 1; $display("PASS  display %0s", what); end
            else begin
                fail = fail + 1;
                $display("FAIL  display %0s : got %0d %0d %0d %0d %0d %0d", what,
                         disp[29:25], disp[24:20], disp[19:15], disp[14:10], disp[9:5], disp[4:0]);
            end
        end
    endtask

    localparam D = 5'd10, BL = 5'd15, Cb = 5'd16, CC = 5'd18, CE = 5'd20, Cr = 5'd21,
               Cd = 5'd22, CP = 5'd23, Cq = 5'd24;
    localparam SC_B = 8'h32, SC_X = 8'h22, SC_SPACE = 8'h29, SC_ENTER = 8'h5A, SC_ESC = 8'h76;
    localparam SC_1 = 8'h16, SC_2 = 8'h1E, SC_4 = 8'h25, SC_5 = 8'h2E, SC_6 = 8'h36, SC_9 = 8'h46;

    reg [11:0] bytes [0:1023];
    reg [31:0] exp   [0:63];
    reg [31:0] meta  [0:0];
    integer i, n_exp, mism;

    initial begin
        $readmemh("vectors/kb_bytes.hex", bytes);
        $readmemh("vectors/kb_exp.hex",   exp);
        $readmemh("vectors/kb_meta.hex",  meta);
        repeat (3) @(posedge clk);
        resetn = 1;
        #1000;

        // ---------------- part 1: typed lines vs the Python model ----------------
        $display("part 1 starts at %0d ns", $time);
        for (i = 0; bytes[i] !== 12'hFFF; i = i + 1)
            ps2_send(bytes[i][7:0], bytes[i][8]);
        #(PS2_HALF * 10);
        $display("part 1 ends at %0d ns (%0d PS/2 bytes)", $time, i);

        n_exp = 0;
        while (exp[n_exp] !== 32'hFFFFFFFF) n_exp = n_exp + 1;
        mism = 0;
        for (i = 0; i < n_exp && i < n_got; i = i + 1)
            if (got[i] !== exp[i]) begin
                mism = mism + 1;
                $display("FAIL  message %0d: got %h expected %h", i, got[i], exp[i]);
            end
        if (n_got == n_exp && mism == 0) begin
            pass = pass + 1; $display("PASS  %0d messages match python/order_entry.py", n_got);
        end else begin
            fail = fail + 1; $display("FAIL  got %0d messages, expected %0d (%0d differ)", n_got, n_exp, mism);
        end
        if (err_count == meta[0]) begin pass = pass + 1; $display("PASS  %0d entries rejected (Err), as expected", err_count); end
        else begin fail = fail + 1; $display("FAIL  %0d rejected, expected %0d", err_count, meta[0]); end
        if (frame_errs == 1) begin pass = pass + 1; $display("PASS  bad-parity frame dropped (frame_err = 1)"); end
        else begin fail = fail + 1; $display("FAIL  frame errors = %0d, expected 1", frame_errs); end

        // ---------------- part 2: what the HEX displays show ----------------
        $display("part 2 starts at %0d ns", $time);
        press(SC_ESC);                         check_disp({6{D}},                    "Esc: - - - - - -");
        press(SC_B); press(SC_1); press(SC_2); check_disp({Cb, CP, BL, BL, 5'd1, 5'd2}, "B12: b P _ _ 1 2");
        press(SC_SPACE); press(SC_5);          check_disp({Cb, Cq, BL, BL, BL, 5'd5}, "space 5: b q _ _ _ 5");
        press(SC_ENTER); #(PS2_HALF * 4);
        check_disp({Cb, Cd, 5'd0, 5'd0, 5'd0, 5'd9},                                   "Enter: b d 0 0 0 9 (id 9)");
        press(SC_X); press(SC_4);              check_disp({CC, Cd, BL, BL, BL, 5'd4}, "X4: C d _ _ _ 4");
        press(SC_ENTER); #(PS2_HALF * 4);
        check_disp({CC, Cd, 5'd0, 5'd0, 5'd0, 5'd4},                                   "Enter: C d 0 0 0 4");
        press(SC_B); press(SC_6); press(SC_9); press(SC_SPACE); press(SC_1); press(SC_ENTER);
        check_disp({CE, Cr, Cr, BL, BL, BL},                                            "B69 1: E r r");
        $display("part 2 ends at %0d ns", $time);

        $display("----------------------------------------");
        $display("%0d checks passed, %0d failed  =>  %0s", pass, fail, fail ? "FAIL" : "ALL PASS");
        $stop;
    end
endmodule
