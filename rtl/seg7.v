// seg7.v  (shared)
// Drives one DE1-SoC 7-segment display (active-low segments, bit order gfedcba).
// d = 0..9 shows the digit, 10 shows '-', anything else is blank.
module seg7 (
    input      [3:0] d,
    output reg [6:0] seg
);
    always @* begin
        case (d)
            4'd0:  seg = 7'b1000000;
            4'd1:  seg = 7'b1111001;
            4'd2:  seg = 7'b0100100;
            4'd3:  seg = 7'b0110000;
            4'd4:  seg = 7'b0011001;
            4'd5:  seg = 7'b0010010;
            4'd6:  seg = 7'b0000010;
            4'd7:  seg = 7'b1111000;
            4'd8:  seg = 7'b0000000;
            4'd9:  seg = 7'b0010000;
            4'd10: seg = 7'b0111111;   // dash
            default: seg = 7'b1111111; // blank
        endcase
    end
endmodule
