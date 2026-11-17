// feed_handler.v  (Parth)
// Reads market messages out of the ROM one at a time, decodes them, hands each
// one to the order book, and waits until the book has finished before moving on.
//
// Message word:  [31:30] type  [29] side  [28:23] price  [22:13] order ID  [12:0] qty
// type: 00 ADD, 01 CANCEL, 10 TRADE, 11 END (stop)
//
// FSM:  IDLE --go--> READ --> LATCH --> SEND --(book ready)--> WAIT --(book done)--> IDLE
//                              |
//                              +--(END word)--> FINISHED
module feed_handler #(
    parameter ADDR_W = 10
) (
    input                   clk,
    input                   resetn,
    input                   go,          // process one message per pulse; hold high to run at full speed

    // ROM interface
    output reg [ADDR_W-1:0] rom_addr,
    input      [31:0]       rom_q,

    // To the order book (valid/ready handshake + done)
    output                  msg_valid,
    output     [1:0]        msg_type,
    output                  msg_side,
    output     [5:0]        msg_price,
    output     [9:0]        msg_id,
    output     [12:0]       msg_qty,
    input                   book_ready,
    input                   book_done,

    // Status
    output reg              msg_start,   // 1-cycle pulse when a new message is read (latency counter start, M3)
    output                  feed_end,    // high once the END word is reached
    output reg [ADDR_W:0]   msg_count,   // messages fully processed
    output     [2:0]        state_out    // for LEDs / debugging
);
    localparam S_IDLE     = 3'd0,
               S_READ     = 3'd1,
               S_LATCH    = 3'd2,
               S_SEND     = 3'd3,
               S_WAIT     = 3'd4,
               S_FINISHED = 3'd5;

    reg [2:0]  state;
    reg [31:0] msg;                       // the message currently being processed

    assign msg_type  = msg[31:30];
    assign msg_side  = msg[29];
    assign msg_price = msg[28:23];
    assign msg_id    = msg[22:13];
    assign msg_qty   = msg[12:0];

    assign msg_valid = (state == S_SEND);
    assign feed_end  = (state == S_FINISHED);
    assign state_out = state;

    always @(posedge clk) begin
        if (!resetn) begin
            state     <= S_IDLE;
            rom_addr  <= 0;
            msg       <= 32'd0;
            msg_start <= 1'b0;
            msg_count <= 0;
        end else begin
            msg_start <= 1'b0;
            case (state)
                S_IDLE:   if (go) state <= S_READ;

                // rom_addr is stable this cycle, so rom_q is valid in the next state
                S_READ:   state <= S_LATCH;

                S_LATCH: begin
                    msg <= rom_q;
                    if (rom_q[31:30] == 2'b11)
                        state <= S_FINISHED;          // END word: stop the feed
                    else begin
                        msg_start <= 1'b1;
                        state     <= S_SEND;
                    end
                end

                // msg_valid is high here; the book accepts it when it is ready
                S_SEND:   if (book_ready) state <= S_WAIT;

                S_WAIT: if (book_done) begin
                    rom_addr  <= rom_addr + 1'b1;
                    msg_count <= msg_count + 1'b1;
                    state     <= S_IDLE;
                end

                S_FINISHED: state <= S_FINISHED;      // stay here until reset

                default:  state <= S_IDLE;
            endcase
        end
    end
endmodule
