// ps2_rx.v  (Parth, M2)
// Receive-only PS/2 interface: turns the keyboard's serial clock/data lines into
// bytes (scan codes). We never send commands to the keyboard, so only the receive
// half of the protocol is needed.
//
// PS/2 frame (keyboard drives both lines, data is read on the FALLING edge of ps2_clk,
// ps2_clk is 10-16.7 kHz, idle high):
//   start (0) | d0 d1 ... d7 (LSB first) | parity (odd) | stop (1)     = 11 bits
//
// How it works
//   * ps2_clk and ps2_dat are asynchronous: 2-flop synchronisers, then a 3rd flop
//     on the clock line to find its falling edge (clk_prev = 1, clk_now = 0).
//   * On each falling edge the data bit is shifted into an 11-bit register
//     (shift right, so the first bit ends up in bit 0) and the bit counter counts.
//   * After the 11th bit the frame is checked (start = 0, stop = 1, odd parity).
//     Good frame: rx_valid pulses for one cycle with the byte. Bad frame: frame_err pulses.
//   * If the keyboard stops half way through a frame (plugged in mid-frame, noise),
//     a timeout of TIMEOUT cycles with no clock edge resets the bit counter, so the
//     next frame starts clean.
module ps2_rx #(
    parameter TIMEOUT = 50_000            // 1 ms at 50 MHz (one frame takes < 1.1 ms; a bit < 0.1 ms)
) (
    input            clk,
    input            resetn,
    input            ps2_clk,             // raw pins
    input            ps2_dat,
    output reg [7:0] rx_byte,
    output reg       rx_valid,            // 1-cycle pulse: rx_byte is a new scan-code byte
    output reg       frame_err            // 1-cycle pulse: bad start/stop/parity (frame dropped)
);
    // ---------------- synchronise + edge detect ----------------
    reg [2:0] clk_s;                      // [0],[1] synchroniser, [2] previous value
    reg [1:0] dat_s;
    always @(posedge clk) begin
        if (!resetn) begin
            clk_s <= 3'b111; dat_s <= 2'b11;
        end else begin
            clk_s <= {clk_s[1:0], ps2_clk};
            dat_s <= {dat_s[0], ps2_dat};
        end
    end
    wire fall = clk_s[2] & ~clk_s[1];     // was high, now low
    wire bit_in = dat_s[1];

    // ---------------- shift register + bit counter ----------------
    reg [10:0] sh;
    reg [3:0]  nbits;                     // bits received so far in this frame
    reg [16:0] idle;                      // cycles since the last falling edge

    wire [10:0] frame = {bit_in, sh[10:1]};                 // register value after this bit
    wire        good  = (frame[0] == 1'b0) && (frame[10] == 1'b1) && (^frame[9:1] == 1'b1);

    always @(posedge clk) begin
        if (!resetn) begin
            sh <= 11'd0; nbits <= 4'd0; idle <= 17'd0;
            rx_byte <= 8'd0; rx_valid <= 1'b0; frame_err <= 1'b0;
        end else begin
            rx_valid  <= 1'b0;
            frame_err <= 1'b0;
            if (fall) begin
                sh   <= frame;
                idle <= 17'd0;
                if (nbits == 4'd10) begin                  // this was the 11th bit
                    nbits <= 4'd0;
                    if (good) begin rx_byte <= frame[8:1]; rx_valid <= 1'b1; end
                    else            frame_err <= 1'b1;
                end else
                    nbits <= nbits + 1'b1;
            end else if (nbits != 4'd0) begin
                if (idle == TIMEOUT) begin nbits <= 4'd0; idle <= 17'd0; end   // give up on this frame
                else idle <= idle + 1'b1;
            end
        end
    end
endmodule
