// kb_decoder.v  (Parth, M2)
// Turns PS/2 scan-code bytes (set 2) into key events for order entry.
//
// A key press sends its make code (e.g. 32 for B). A release sends F0 then the
// make code. Some keys (keypad Enter, arrows) send E0 first. So:
//   F0      -> the next code is a release: ignore it
//   E0      -> the next code is an extended key (only keypad Enter is used)
//   other   -> a key press: look it up, pulse key_valid if it is a key we use
// Holding a key down repeats its make code (typematic), which simply types it again.
//
// Key codes (key_code):
//   0..9  digits (top row or keypad)
//   10 B (buy)   11 S or A (sell / ask)   12 X or C (cancel)   13 T (trade)
//   14 Space     15 Enter (either)        16 Esc               17 Backspace
module kb_decoder (
    input            clk,
    input            resetn,
    input      [7:0] rx_byte,
    input            rx_valid,
    output reg       key_valid,          // 1-cycle pulse
    output reg [4:0] key_code
);
    localparam K_BUY = 5'd10, K_SELL = 5'd11, K_CANCEL = 5'd12, K_TRADE = 5'd13,
               K_SPACE = 5'd14, K_ENTER = 5'd15, K_ESC = 5'd16, K_BKSP = 5'd17;

    reg brk, ext;                        // last byte was F0 / E0

    // {known, code} for a make code
    function [5:0] lookup(input [7:0] sc, input e);
        begin
            if (e) lookup = (sc == 8'h5A) ? {1'b1, K_ENTER} : 6'd0;   // keypad Enter only
            else case (sc)
                8'h45, 8'h70: lookup = {1'b1, 5'd0};
                8'h16, 8'h69: lookup = {1'b1, 5'd1};
                8'h1E, 8'h72: lookup = {1'b1, 5'd2};
                8'h26, 8'h7A: lookup = {1'b1, 5'd3};
                8'h25, 8'h6B: lookup = {1'b1, 5'd4};
                8'h2E, 8'h73: lookup = {1'b1, 5'd5};
                8'h36, 8'h74: lookup = {1'b1, 5'd6};
                8'h3D, 8'h6C: lookup = {1'b1, 5'd7};
                8'h3E, 8'h75: lookup = {1'b1, 5'd8};
                8'h46, 8'h7D: lookup = {1'b1, 5'd9};
                8'h32:        lookup = {1'b1, K_BUY};     // B
                8'h1B, 8'h1C: lookup = {1'b1, K_SELL};    // S, A
                8'h22, 8'h21: lookup = {1'b1, K_CANCEL};  // X, C
                8'h2C:        lookup = {1'b1, K_TRADE};   // T
                8'h29:        lookup = {1'b1, K_SPACE};
                8'h5A:        lookup = {1'b1, K_ENTER};
                8'h76:        lookup = {1'b1, K_ESC};
                8'h66:        lookup = {1'b1, K_BKSP};
                default:      lookup = 6'd0;
            endcase
        end
    endfunction

    wire [5:0] hit = lookup(rx_byte, ext);

    always @(posedge clk) begin
        if (!resetn) begin
            brk <= 1'b0; ext <= 1'b0; key_valid <= 1'b0; key_code <= 5'd0;
        end else begin
            key_valid <= 1'b0;
            if (rx_valid) begin
                if (rx_byte == 8'hF0)      brk <= 1'b1;
                else if (rx_byte == 8'hE0) ext <= 1'b1;
                else begin
                    if (!brk && hit[5]) begin key_valid <= 1'b1; key_code <= hit[4:0]; end
                    brk <= 1'b0; ext <= 1'b0;
                end
            end
        end
    end
endmodule
