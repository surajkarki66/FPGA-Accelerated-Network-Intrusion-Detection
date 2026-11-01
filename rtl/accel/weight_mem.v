// Weight / bias Read-only Memory (ROM)
// Layout : per-layer row-major (out, in), then biases.

`timescale 1ns / 1ps
`include "fnn_params.vh"

// Module declaration and parameters
module weight_mem #(
    parameter DATA_W   = `FNN_DATA_W,
    parameter DEPTH    = `FNN_W_DEPTH, // total number of memory location
    parameter ADDR_W   = `FNN_W_ADDR_W, // the number of bits required to address the memory
    parameter MEM_FILE = ""
) (
    input  wire              clk,
    input  wire [ADDR_W-1:0] addr,  // address input
    output reg signed [DATA_W-1:0] dout // sends output to another module
);
    (* ram_style = "block" *) reg signed [DATA_W-1:0] mem [0:DEPTH-1]; // mapped to BlockRAM
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = {DATA_W{1'b0}}; // memory initializing to zero
        if (MEM_FILE != "")
            $readmemh(MEM_FILE, mem); // reads hexadecimal values from a text file and loads them into consecutive memory locations.
    end

    // Synchronous read operation
    always @(posedge clk)
        dout <= mem[addr];
endmodule
