// sync2.v  (Pierce)
// Two flip-flop synchroniser for asynchronous board inputs (switches, keys).
// The first flop may go metastable; the second gives it a full cycle to settle.
module sync2 #(
    parameter WIDTH = 1
) (
    input                  clk,
    input      [WIDTH-1:0] d,
    output reg [WIDTH-1:0] q
);
    reg [WIDTH-1:0] meta;
    always @(posedge clk) begin
        meta <= d;
        q    <= meta;
    end
endmodule
