// seg7.v  (shared)
// Drives one DE1-SoC 7-segment display (active-low segments, bit order gfedcba).
// d = 0..9 shows the digit, 10 shows '-', 15 (or anything unused) is blank.
// M2 (Parth): widened to 5 bits for letters used by the keyboard and fills views.
// Codes 0..15 mean the same as before; 4-bit callers must pad with a 0 ({1'b0, d}),
// because ModelSim leaves an unconnected port bit as z (which shows blank).
//   16 b   17 S   18 C   19 t   20 E   21 r   22 d   23 P   24 q   25 F
module seg7 (
    input      [4:0] d,
    output reg [6:0] seg
);
    always @* begin
        case (d)
            5'd0:  seg = 7'b1000000;
            5'd1:  seg = 7'b1111001;
            5'd2:  seg = 7'b0100100;
            5'd3:  seg = 7'b0110000;
            5'd4:  seg = 7'b0011001;
            5'd5:  seg = 7'b0010010;
            5'd6:  seg = 7'b0000010;
            5'd7:  seg = 7'b1111000;
            5'd8:  seg = 7'b0000000;
            5'd9:  seg = 7'b0010000;
            5'd10: seg = 7'b0111111;   // dash
            5'd16: seg = 7'b0000011;   // b
            5'd17: seg = 7'b0010010;   // S
            5'd18: seg = 7'b1000110;   // C
            5'd19: seg = 7'b0000111;   // t
            5'd20: seg = 7'b0000110;   // E
            5'd21: seg = 7'b0101111;   // r
            5'd22: seg = 7'b0100001;   // d
            5'd23: seg = 7'b0001100;   // P
            5'd24: seg = 7'b0011000;   // q
            5'd25: seg = 7'b0001110;   // F
            default: seg = 7'b1111111; // blank
        endcase
    end
endmodule
