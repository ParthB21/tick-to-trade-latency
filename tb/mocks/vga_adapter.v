// vga_adapter.v  (Pierce)  SIMULATION ONLY - never add this file to Quartus.
// Stand-in for the course vga_adapter with the same ports and parameters.
// Instead of driving a monitor it stores plotted pixels in fb[y*320 + x],
// which the testbench dumps with $writememh and python/e2e.py turns into a PNG.
module vga_adapter #(
    parameter RESOLUTION              = "320x240",
    parameter MONOCHROME              = "FALSE",
    parameter BITS_PER_COLOUR_CHANNEL = 1,
    parameter BACKGROUND_IMAGE        = "black.mif"
) (
    input        resetn,
    input        clock,
    input  [2:0] colour,
    input  [8:0] x,
    input  [7:0] y,
    input        plot,
    output [7:0] VGA_R, VGA_G, VGA_B,
    output       VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK
);
    localparam WIDTH = 320, HEIGHT = 240, BLACK = 3'b000;

    reg [2:0] fb [0:WIDTH*HEIGHT-1];
    integer i;
    initial for (i = 0; i < WIDTH*HEIGHT; i = i + 1) fb[i] = BLACK;   // black.mif background

    always @(posedge clock)
        if (plot) fb[y * WIDTH + x] <= colour;

    assign {VGA_R, VGA_G, VGA_B} = 24'd0;
    assign {VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK} = 5'd0;
endmodule
