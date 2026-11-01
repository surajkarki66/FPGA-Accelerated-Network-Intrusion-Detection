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
    // Memory array declaration
    reg signed [DATA_W-1:0] mem [0:DEPTH-1]; // [DATA_W-1:0]: Defines the bit width of each memory location, mem: Name of the memory array, [0:DEPTH-1]: Defines the memory address range.
    // Declare an integer variable
    integer i;

    // Memory initialization
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = {DATA_W{1'b0}};  // Initializes all memory locations to zero.
    end

    // Synchronous memory operation
    // Reading and writing can happen during the same clock cycle.
    // If both addresses point to the same location, the RTL code reads the old value because non-blocking assignments update the memory after evaluating the right-hand sides.
    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata; // Non-blocking assignment
        rdata <= mem[raddr];
    end
endmodule
