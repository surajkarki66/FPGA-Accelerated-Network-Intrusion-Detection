// Weight / bias ROM. DEPTH should match the .mem file (FNN_W_DEPTH / FNN_B_DEPTH).
// Layout (sw/model/export_weights.py): per-layer row-major (out, in), then biases.
// To grow the net: train/deploy with new --layers; params.vh depths update automatically.
`timescale 1ns / 1ps
`include "fnn_params.vh"

module weight_mem #(
    parameter DATA_W   = `FNN_DATA_W,
    parameter DEPTH    = `FNN_W_DEPTH,
    parameter ADDR_W   = `FNN_W_ADDR_W,
    parameter MEM_FILE = ""
) (
    input  wire              clk,
    input  wire [ADDR_W-1:0] addr,
    output reg signed [DATA_W-1:0] dout
);
    (* ram_style = "block" *) reg signed [DATA_W-1:0] mem [0:DEPTH-1];
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = {DATA_W{1'b0}};
        if (MEM_FILE != "")
            $readmemh(MEM_FILE, mem);
    end

    always @(posedge clk)
        dout <= mem[addr];
endmodule
