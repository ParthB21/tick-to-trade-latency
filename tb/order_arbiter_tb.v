// order_arbiter_tb.v  (Parth, M2)
// Tests the arbiter on its own, with three simple stand-ins:
//   feed stub  : behaves like feed_handler (holds valid until ready, waits for done,
//                then GAP cycles before the next message; GAP = 3 like the real one,
//                GAP = 0 for back-to-back)
//   kbd stub   : behaves like order_entry (holds valid until ready)
//   book stub  : same handshake and timing as order_book (accept on IDLE,
//                done 4 cycles later for ADD, 5 for CANCEL), logs every message it gets
// Every message carries a unique tag in its order-ID field. At the end the log is
// checked: every message sent arrives exactly once, in order per source, and every
// done goes back to the right source.
//
// Cases (start times are printed, use them to zoom the waveform):
//   1 same-cycle requests          -> keyboard first, then feed
//   2 keyboard while book is busy with a feed message -> waits, goes next
//   3 back-to-back feed (GAP 0) with a keyboard message in the middle,
//     including a keyboard request in the same cycle as the next feed message
//   4 stress: 300 feed messages (random gaps) + 60 keyboard messages at random times
`timescale 1ns/1ps
module order_arbiter_tb;
    reg clk = 0;
    always #10 clk = ~clk;
    reg resetn = 0;

    // ---------------- DUT ----------------
    reg         f_valid = 0, k_valid = 0;
    reg  [31:0] f_msg = 0, k_msg = 0;
    wire        f_ready, f_done, k_ready, k_done;
    wire        b_valid, b_side, owner;
    wire [1:0]  b_type, arb_state;
    wire [5:0]  b_price;
    wire [10:0] b_id;
    wire [12:0] b_qty;
    reg         b_ready_r;
    wire        b_ready = b_ready_r;
    reg         b_done = 0;
    wire [9:0]  f_tag = f_msg[22:13];             // message tags, for the waveform
    wire [9:0]  k_tag = k_msg[22:13];

    order_arbiter dut (
        .clk(clk), .resetn(resetn),
        .f_valid(f_valid), .f_msg(f_msg), .f_ready(f_ready), .f_done(f_done),
        .k_valid(k_valid), .k_msg(k_msg), .k_ready(k_ready), .k_done(k_done),
        .b_valid(b_valid), .b_type(b_type), .b_side(b_side), .b_price(b_price),
        .b_id(b_id), .b_qty(b_qty), .b_ready(b_ready), .b_done(b_done),
        .owner(owner), .state_out(arb_state)
    );

    // message with a tag in the ID field; tag bit 0 picks ADD (4 cycles) or CANCEL (5 cycles)
    function [31:0] mk(input [9:0] tag);
        mk = {tag[0] ? 2'b01 : 2'b00, 1'b0, 6'd20, tag, 13'd100};
    endfunction

    // ---------------- book stub ----------------
    localparam MAXLOG = 1024;
    reg  [10:0] log_id [0:MAXLOG-1];
    integer     n_log = 0, busy = 0;
    reg  [2:0]  bstate = 0;                       // 0 idle, 1 busy, 2 done (like the real book)
    reg  [10:0] cur;
    integer     wrong_done = 0, f_dones = 0, k_dones = 0;

    always @* b_ready_r = (bstate == 0) && resetn;

    always @(posedge clk) begin
        b_done <= 0;
        case (bstate)
            0: if (b_valid && b_ready) begin
                   log_id[n_log] = b_id; n_log = n_log + 1;
                   if ($time < 1500)                  // cases 1-3: times for the waveform notes
                       $display("  %0d ns: book accepts %s %0d", $time, b_id[10] ? "KBD " : "FEED", b_id[9:0]);
                   cur = b_id;
                   busy  = (b_type == 2'b00) ? 2 : 3; // + this busy count + DONE = 4 / 5 cycles
                   bstate <= 1;
               end
            1: if (busy == 0) begin bstate <= 2; b_done <= 1; end else busy = busy - 1;
            2: bstate <= 0;
        endcase
    end

    always @(posedge clk) begin                   // done must go to the owner only
        if (f_done) begin f_dones = f_dones + 1; if (cur[10] !== 1'b0) wrong_done = wrong_done + 1; end
        if (k_done) begin k_dones = k_dones + 1; if (cur[10] !== 1'b1) wrong_done = wrong_done + 1; end
        if (f_done && k_done) wrong_done = wrong_done + 1;
    end

    // ---------------- source stubs ----------------
    integer f_sent = 0, k_sent = 0;
    integer gap = 3;

    task feed_send(input [9:0] tag);              // like feed_handler SEND + WAIT
        begin
            @(negedge clk); f_msg = mk(tag); f_valid = 1;
            @(posedge clk); while (!f_ready) @(posedge clk);
            #1 f_valid = 0; f_sent = f_sent + 1;
            @(posedge clk); while (!f_done) @(posedge clk);
            repeat (gap) @(posedge clk);
        end
    endtask

    task kb_send(input [9:0] tag);                // like order_entry SEND
        begin
            @(negedge clk); k_msg = mk(tag); k_valid = 1;
            @(posedge clk); while (!k_ready) @(posedge clk);
            #1 k_valid = 0; k_sent = k_sent + 1;
        end
    endtask

    // ---------------- checks ----------------
    integer pass = 0, fail = 0;

    task expect_order(input integer first, input [10:0] a, input [10:0] b, input [10:0] c,
                      input integer n, input [8*64-1:0] what);
        reg ok;
        begin
            ok = (log_id[first] === a) && (n < 2 || log_id[first+1] === b) && (n < 3 || log_id[first+2] === c);
            if (ok) begin pass = pass + 1; $display("PASS  %0s", what); end
            else begin
                fail = fail + 1;
                $display("FAIL  %0s : got %h %h %h", what, log_id[first], log_id[first+1], log_id[first+2]);
            end
        end
    endtask

    integer i, j, base, last_f, last_k, f_seen, k_seen, dup;
    integer t0;

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk) resetn = 1;
        repeat (2) @(posedge clk);

        // ---- case 1: both request in the same cycle ----
        t0 = $time; base = n_log;
        $display("case 1 starts at %0d ns", t0);
        fork
            feed_send(10'd2);
            kb_send(10'd700);
        join
        expect_order(base, {1'b1, 10'd700}, {1'b0, 10'd2}, 0, 2, "case 1: same cycle -> keyboard, then feed");
        $display("case 1 ends at %0d ns", $time);
        repeat (4) @(posedge clk);

        // ---- case 2: keyboard arrives while the book is busy with a feed message ----
        t0 = $time; base = n_log;
        $display("case 2 starts at %0d ns", t0);
        fork
            begin feed_send(10'd4); feed_send(10'd6); end
            begin
                @(posedge clk); while (!(b_valid && b_ready)) @(posedge clk);   // feed 4 accepted
                @(posedge clk);                                                   // book busy now
                kb_send(10'd702);
            end
        join
        expect_order(base, {1'b0, 10'd4}, {1'b1, 10'd702}, {1'b0, 10'd6}, 3,
                     "case 2: kbd while busy -> F4, K702, F6");
        $display("case 2 ends at %0d ns", $time);
        repeat (4) @(posedge clk);

        // ---- case 3: back-to-back feed with keyboard messages in between ----
        gap = 0;
        t0 = $time; base = n_log;
        $display("case 3 starts at %0d ns", t0);
        fork
            begin feed_send(10'd8); feed_send(10'd10); feed_send(10'd12); feed_send(10'd14); end
            begin
                @(posedge clk); while (!(b_valid && b_ready)) @(posedge clk);   // F8 accepted
                kb_send(10'd704);                                                 // raised while F8 busy
                @(posedge clk); while (!(f_done && cur[9:0] == 10'd10)) @(posedge clk);
                kb_send(10'd706);         // raised in the same cycle the feed presents F12
            end
        join
        expect_order(base,     {1'b0, 10'd8},  {1'b1, 10'd704}, {1'b0, 10'd10}, 3,
                     "case 3a: F8, K704, F10 (feed back-to-back)");
        expect_order(base + 3, {1'b1, 10'd706}, {1'b0, 10'd12}, {1'b0, 10'd14}, 3,
                     "case 3b: K706 and F12 same cycle -> K706, F12, F14");
        $display("case 3 ends at %0d ns", $time);
        repeat (4) @(posedge clk);

        // ---- case 4: stress ----
        t0 = $time; base = n_log;
        $display("case 4 starts at %0d ns (stress)", t0);
        fork
            for (i = 0; i < 300; i = i + 1) begin
                gap = $urandom % 4;
                feed_send(10'd100 + i);
            end
            for (j = 0; j < 60; j = j + 1) begin
                repeat ($urandom % 50) @(posedge clk);
                kb_send(10'd800 + j);
            end
        join
        repeat (8) @(posedge clk);

        // every message exactly once and in order, per source
        last_f = -1; last_k = -1; f_seen = 0; k_seen = 0; dup = 0;
        for (i = base; i < n_log; i = i + 1) begin
            if (log_id[i][10] == 1'b0) begin
                if (log_id[i][9:0] != 10'd100 + f_seen) dup = dup + 1;
                f_seen = f_seen + 1;
            end else begin
                if (log_id[i][9:0] != 10'd800 + k_seen) dup = dup + 1;
                k_seen = k_seen + 1;
            end
        end
        if (f_seen == 300 && k_seen == 60 && dup == 0) begin
            pass = pass + 1;
            $display("PASS  case 4: 300 feed + 60 kbd sent, book got %0d feed + %0d kbd, none lost, none repeated, in order",
                     f_seen, k_seen);
        end else begin
            fail = fail + 1;
            $display("FAIL  case 4: book got %0d feed (300 sent) %0d kbd (60 sent), %0d out of order/duplicate",
                     f_seen, k_seen, dup);
        end
        $display("case 4 ends at %0d ns", $time);

        // totals over all cases
        if (n_log == f_sent + k_sent && f_dones == f_sent && k_dones == k_sent && wrong_done == 0) begin
            pass = pass + 1;
            $display("PASS  totals: sent %0d feed + %0d kbd = %0d, book received %0d, done to feed %0d, to kbd %0d, misrouted 0",
                     f_sent, k_sent, f_sent + k_sent, n_log, f_dones, k_dones);
        end else begin
            fail = fail + 1;
            $display("FAIL  totals: sent %0d+%0d, received %0d, dones %0d/%0d, misrouted %0d",
                     f_sent, k_sent, n_log, f_dones, k_dones, wrong_done);
        end

        $display("----------------------------------------");
        $display("%0d checks passed, %0d failed  =>  %0s", pass, fail, fail ? "FAIL" : "ALL PASS");
        $stop;
    end

    initial begin #2_000_000; $display("TIMEOUT"); $stop; end
endmodule
