// Dual-port-ish activation scratchpad (simple dual arrays for ping/pong).
// Synthesizes to BRAM/LUTRAM depending on size.
`timescale 1ns / 1ps
`include "fnn_params.vh"

module act_mem #(
    parameter DATA_W = `FNN_DATA_W,
    parameter DEPTH  = `FNN_MAX_IN,
    parameter ADDR_W = `FNN_ACT_ADDR_W
) (
    input  wire                 clk,
    input  wire                 we,
    input  wire [ADDR_W-1:0]    waddr,
    input  wire signed [DATA_W-1:0] wdata,
    input  wire [ADDR_W-1:0]    raddr,
    output reg  signed [DATA_W-1:0] rdata
);
    reg signed [DATA_W-1:0] mem [0:DEPTH-1];
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = {DATA_W{1'b0}};
    end

    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end
endmodule
