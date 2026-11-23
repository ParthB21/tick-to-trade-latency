// bin2bcd.v  (Pierce)
// Sequential binary to BCD (shift-and-add-3, one bit per clock, no divider).
// A start pulse loads value; BITS cycles later bcd holds its decimal digits.
// bcd keeps the previous result while a conversion runs, so a reader never sees
// half-converted digits. value must be < 10^DIGITS (the caller clamps it).
module bin2bcd #(
    parameter BITS   = 17,
    parameter DIGITS = 5
) (
    input                         clk,
    input                         resetn,
    input                         start,
    input      [BITS-1:0]         value,
    output reg [4*DIGITS-1:0]     bcd
);
    localparam COUNT_W = $clog2(BITS + 1);

    reg [BITS-1:0]     bin;
    reg [4*DIGITS-1:0] acc, adj;
    reg [COUNT_W-1:0]  count;
    integer d;

    // add 3 to every digit >= 5 so the next shift carries into the digit above
    always @* begin
        adj = acc;
        for (d = 0; d < DIGITS; d = d + 1)
            if (acc[4*d +: 4] >= 4'd5) adj[4*d +: 4] = acc[4*d +: 4] + 4'd3;
    end

    always @(posedge clk) begin
        if (!resetn) begin
            bin <= {BITS{1'b0}}; acc <= {4*DIGITS{1'b0}}; count <= {COUNT_W{1'b0}};
            bcd <= {4*DIGITS{1'b0}};
        end else if (start) begin
            bin <= value; acc <= {4*DIGITS{1'b0}}; count <= BITS;
        end else if (count != {COUNT_W{1'b0}}) begin
            {acc, bin} <= {adj, bin} << 1;
            count <= count - 1'b1;
            if (count == 1) bcd <= {adj[4*DIGITS-2:0], bin[BITS-1]};
        end
    end
endmodule
