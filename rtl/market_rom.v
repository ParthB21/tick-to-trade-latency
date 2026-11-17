// market_rom.v  (Parth)
// Holds the recorded market messages. One 32-bit message per address.
// Synchronous read: q is valid on the clock edge AFTER addr is applied.
// $readmemh works in both ModelSim and Quartus (Quartus turns it into the
// RAM block's initial contents). The path is relative to the Quartus project
// folder (or the ModelSim working folder).
module market_rom #(
    parameter DEPTH     = 1024,
    parameter ADDR_W    = 10,
    parameter INIT_FILE = "market_data.hex"
) (
    input                   clk,
    input  [ADDR_W-1:0]     addr,
    output reg [31:0]       q
);
    reg [31:0] mem [0:DEPTH-1];

    // gen_market.py pads the .hex file with END words up to DEPTH
    initial $readmemh(INIT_FILE, mem);

    always @(posedge clk)
        q <= mem[addr];
endmodule
