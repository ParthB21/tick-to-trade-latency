// font_rom.v  (Pierce)
// 5x7 glyphs for the dashboard text: digits, sign, and the letters of "POS" / "PNL".
// bits[4] is the leftmost pixel of the row. Unknown codes are blank.
module font_rom (
    input      [4:0] glyph,
    input      [2:0] row,          // 0 = top
    output reg [4:0] bits
);
    // glyph codes 0..9 are the digits themselves
    localparam G_PLUS = 5'd10, G_MINUS = 5'd11, G_P = 5'd12, G_O = 5'd13,
               G_S = 5'd14, G_N = 5'd15, G_L = 5'd16;

    always @* begin
        case ({glyph, row})
            {5'd0, 3'd0}: bits = 5'b01110;  {5'd0, 3'd1}: bits = 5'b10001;  {5'd0, 3'd2}: bits = 5'b10011;
            {5'd0, 3'd3}: bits = 5'b10101;  {5'd0, 3'd4}: bits = 5'b11001;  {5'd0, 3'd5}: bits = 5'b10001;
            {5'd0, 3'd6}: bits = 5'b01110;
            {5'd1, 3'd0}: bits = 5'b00100;  {5'd1, 3'd1}: bits = 5'b01100;  {5'd1, 3'd2}: bits = 5'b00100;
            {5'd1, 3'd3}: bits = 5'b00100;  {5'd1, 3'd4}: bits = 5'b00100;  {5'd1, 3'd5}: bits = 5'b00100;
            {5'd1, 3'd6}: bits = 5'b01110;
            {5'd2, 3'd0}: bits = 5'b01110;  {5'd2, 3'd1}: bits = 5'b10001;  {5'd2, 3'd2}: bits = 5'b00001;
            {5'd2, 3'd3}: bits = 5'b00010;  {5'd2, 3'd4}: bits = 5'b00100;  {5'd2, 3'd5}: bits = 5'b01000;
            {5'd2, 3'd6}: bits = 5'b11111;
            {5'd3, 3'd0}: bits = 5'b11111;  {5'd3, 3'd1}: bits = 5'b00010;  {5'd3, 3'd2}: bits = 5'b00100;
            {5'd3, 3'd3}: bits = 5'b00010;  {5'd3, 3'd4}: bits = 5'b00001;  {5'd3, 3'd5}: bits = 5'b10001;
            {5'd3, 3'd6}: bits = 5'b01110;
            {5'd4, 3'd0}: bits = 5'b00010;  {5'd4, 3'd1}: bits = 5'b00110;  {5'd4, 3'd2}: bits = 5'b01010;
            {5'd4, 3'd3}: bits = 5'b10010;  {5'd4, 3'd4}: bits = 5'b11111;  {5'd4, 3'd5}: bits = 5'b00010;
            {5'd4, 3'd6}: bits = 5'b00010;
            {5'd5, 3'd0}: bits = 5'b11111;  {5'd5, 3'd1}: bits = 5'b10000;  {5'd5, 3'd2}: bits = 5'b11110;
            {5'd5, 3'd3}: bits = 5'b00001;  {5'd5, 3'd4}: bits = 5'b00001;  {5'd5, 3'd5}: bits = 5'b10001;
            {5'd5, 3'd6}: bits = 5'b01110;
            {5'd6, 3'd0}: bits = 5'b00110;  {5'd6, 3'd1}: bits = 5'b01000;  {5'd6, 3'd2}: bits = 5'b10000;
            {5'd6, 3'd3}: bits = 5'b11110;  {5'd6, 3'd4}: bits = 5'b10001;  {5'd6, 3'd5}: bits = 5'b10001;
            {5'd6, 3'd6}: bits = 5'b01110;
            {5'd7, 3'd0}: bits = 5'b11111;  {5'd7, 3'd1}: bits = 5'b00001;  {5'd7, 3'd2}: bits = 5'b00010;
            {5'd7, 3'd3}: bits = 5'b00100;  {5'd7, 3'd4}: bits = 5'b01000;  {5'd7, 3'd5}: bits = 5'b01000;
            {5'd7, 3'd6}: bits = 5'b01000;
            {5'd8, 3'd0}: bits = 5'b01110;  {5'd8, 3'd1}: bits = 5'b10001;  {5'd8, 3'd2}: bits = 5'b10001;
            {5'd8, 3'd3}: bits = 5'b01110;  {5'd8, 3'd4}: bits = 5'b10001;  {5'd8, 3'd5}: bits = 5'b10001;
            {5'd8, 3'd6}: bits = 5'b01110;
            {5'd9, 3'd0}: bits = 5'b01110;  {5'd9, 3'd1}: bits = 5'b10001;  {5'd9, 3'd2}: bits = 5'b10001;
            {5'd9, 3'd3}: bits = 5'b01111;  {5'd9, 3'd4}: bits = 5'b00001;  {5'd9, 3'd5}: bits = 5'b00010;
            {5'd9, 3'd6}: bits = 5'b01100;
            {G_PLUS, 3'd1}: bits = 5'b00100;  {G_PLUS, 3'd2}: bits = 5'b00100;  {G_PLUS, 3'd3}: bits = 5'b11111;
            {G_PLUS, 3'd4}: bits = 5'b00100;  {G_PLUS, 3'd5}: bits = 5'b00100;
            {G_MINUS, 3'd3}: bits = 5'b11111;
            {G_P, 3'd0}: bits = 5'b11110;  {G_P, 3'd1}: bits = 5'b10001;  {G_P, 3'd2}: bits = 5'b10001;
            {G_P, 3'd3}: bits = 5'b11110;  {G_P, 3'd4}: bits = 5'b10000;  {G_P, 3'd5}: bits = 5'b10000;
            {G_P, 3'd6}: bits = 5'b10000;
            {G_O, 3'd0}: bits = 5'b01110;  {G_O, 3'd1}: bits = 5'b10001;  {G_O, 3'd2}: bits = 5'b10001;
            {G_O, 3'd3}: bits = 5'b10001;  {G_O, 3'd4}: bits = 5'b10001;  {G_O, 3'd5}: bits = 5'b10001;
            {G_O, 3'd6}: bits = 5'b01110;
            {G_S, 3'd0}: bits = 5'b01111;  {G_S, 3'd1}: bits = 5'b10000;  {G_S, 3'd2}: bits = 5'b10000;
            {G_S, 3'd3}: bits = 5'b01110;  {G_S, 3'd4}: bits = 5'b00001;  {G_S, 3'd5}: bits = 5'b00001;
            {G_S, 3'd6}: bits = 5'b11110;
            {G_N, 3'd0}: bits = 5'b10001;  {G_N, 3'd1}: bits = 5'b11001;  {G_N, 3'd2}: bits = 5'b10101;
            {G_N, 3'd3}: bits = 5'b10011;  {G_N, 3'd4}: bits = 5'b10001;  {G_N, 3'd5}: bits = 5'b10001;
            {G_N, 3'd6}: bits = 5'b10001;
            {G_L, 3'd0}: bits = 5'b10000;  {G_L, 3'd1}: bits = 5'b10000;  {G_L, 3'd2}: bits = 5'b10000;
            {G_L, 3'd3}: bits = 5'b10000;  {G_L, 3'd4}: bits = 5'b10000;  {G_L, 3'd5}: bits = 5'b10000;
            {G_L, 3'd6}: bits = 5'b11111;
            default: bits = 5'b00000;
        endcase
    end
endmodule
