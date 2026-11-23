// order_arbiter.v  (Parth, M2)
// Merges two message sources into the single order book input, one message at a time:
//   source 0 : feed handler (ROM replay)
//   source 1 : keyboard order entry (PS/2)
// Both use the same 32-bit message format and the same valid/ready handshake the
// feed handler already used with the book.
//
// Collision policy
//   * The book takes one message at a time. A source is granted only when the
//     arbiter is IDLE and the book is ready.
//   * If both request in the same cycle, the KEYBOARD wins (fixed priority).
//     Keyboard messages are rare (a person typing), so the feed can never be starved.
//   * Nothing is lost: a source that is not granted simply keeps valid high.
//     The feed handler stays in SEND with msg_valid = 1 (and its message register
//     unchanged) until f_ready; order entry holds k_valid until k_ready and cannot
//     start another message until then.
//   * done is routed back only to the source that owns the message in the book,
//     so the feed handler's WAIT state never sees a keyboard message's done.
//   * The source bit goes to the book as order-ID bit 10, so keyboard order IDs
//     never collide with ROM order IDs.
//
// FSM:  IDLE --(grant keyboard)--> KBD  --(book done)--> IDLE
//       IDLE --(grant feed)------> FEED --(book done)--> IDLE
module order_arbiter (
    input             clk,
    input             resetn,

    // source 0: feed handler
    input             f_valid,
    input      [31:0] f_msg,
    output            f_ready,
    output            f_done,

    // source 1: keyboard order entry
    input             k_valid,
    input      [31:0] k_msg,
    output            k_ready,
    output            k_done,

    // to the order book
    output            b_valid,
    output     [1:0]  b_type,
    output            b_side,
    output     [5:0]  b_price,
    output     [10:0] b_id,          // {source, order ID}
    output     [12:0] b_qty,
    input             b_ready,
    input             b_done,

    output            owner,         // source of the message the book is working on
    output     [1:0]  state_out
);
    localparam A_IDLE = 2'd0, A_FEED = 2'd1, A_KBD = 2'd2;

    reg [1:0] state;
    assign state_out = state;

    wire idle   = (state == A_IDLE);
    wire pick_k = k_valid;                          // keyboard has priority
    wire [31:0] msg = pick_k ? k_msg : f_msg;

    // only offer a message while IDLE; the book latches it on its own IDLE cycle
    assign b_valid = idle & (k_valid | f_valid);
    assign b_type  = msg[31:30];
    assign b_side  = msg[29];
    assign b_price = msg[28:23];
    assign b_id    = {pick_k, msg[22:13]};
    assign b_qty   = msg[12:0];

    assign k_ready = idle & b_ready & k_valid;
    assign f_ready = idle & b_ready & f_valid & ~k_valid;

    assign owner  = (state == A_KBD);
    assign f_done = b_done & (state == A_FEED);
    assign k_done = b_done & (state == A_KBD);

    always @(posedge clk) begin
        if (!resetn)
            state <= A_IDLE;
        else case (state)
            A_IDLE: if (b_valid && b_ready) state <= pick_k ? A_KBD : A_FEED;
            A_FEED,
            A_KBD:  if (b_done) state <= A_IDLE;
            default: state <= A_IDLE;
        endcase
    end
endmodule
