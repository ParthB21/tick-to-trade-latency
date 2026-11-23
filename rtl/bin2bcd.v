// bin2bcd.v  (Parth, M2)
// Binary (0..16383) to 5 BCD digits with the shift-and-add-3 ("double dabble")
// method: shift the binary number in one bit at a time; before each shift, any
// BCD digit that is 5 or more gets 3 added so it carries correctly into the next
// digit. Purely combinational (14 rows of small adders), no divider.
// Replaces the / 10 and % 10 the M1 HEX code used.
//   bcd[3:0] ones, [7:4] tens, [11:8] hundreds, [15:12] thousands, [19:16] ten-thousands
module bin2bcd (
    input      [13:0] bin,
    output reg [19:0] bcd
);
    integer i;
    always @* begin
        bcd = 20'd0;
        for (i = 13; i >= 0; i = i - 1) begin
            if (bcd[3:0]   >= 4'd5) bcd[3:0]   = bcd[3:0]   + 4'd3;
            if (bcd[7:4]   >= 4'd5) bcd[7:4]   = bcd[7:4]   + 4'd3;
            if (bcd[11:8]  >= 4'd5) bcd[11:8]  = bcd[11:8]  + 4'd3;
            if (bcd[15:12] >= 4'd5) bcd[15:12] = bcd[15:12] + 4'd3;
            bcd = {bcd[18:0], bin[i]};
        end
    end
endmodule
