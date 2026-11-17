// prio_enc64.v  (Parth)
// 64-input priority encoder.
//   HIGHEST = 1 : idx = position of the highest 1 bit  (best bid = highest price with orders)
//   HIGHEST = 0 : idx = position of the lowest 1 bit   (best ask = lowest price with orders)
// valid = 0 when no bits are set (that side of the book is empty).
// Purely combinational, so the answer is ready in the same cycle the mask changes.
module prio_enc64 #(
    parameter HIGHEST = 1
) (
    input      [63:0] in,
    output reg [5:0]  idx,
    output            valid
);
    assign valid = |in;

    integer i;
    always @* begin
        idx = 6'd0;
        if (HIGHEST) begin
            for (i = 0; i < 64; i = i + 1)        // later (higher) bits overwrite earlier ones
                if (in[i]) idx = i[5:0];
        end else begin
            for (i = 63; i >= 0; i = i - 1)       // later (lower) bits overwrite earlier ones
                if (in[i]) idx = i[5:0];
        end
    end
endmodule
