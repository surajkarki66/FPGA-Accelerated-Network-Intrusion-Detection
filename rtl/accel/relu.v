`timescale 1ns / 1ps
`include "fnn_params.vh"

module relu #(
    parameter DATA_W = `FNN_DATA_W
) (
    input  wire signed [DATA_W-1:0] din, // signed input value from the MAC unit
    input  wire                     enable,  // controls whether ReLU is applied
    output wire signed [DATA_W-1:0] dout // output after ReLU or bypass.
);  
    // For a signed two's-complement number, the most significant bit is the sign bit.
    // For INT8: din[7] = 1  → negative, din[7] = 0  → zero or positive
    assign dout = (enable && din[DATA_W-1]) ? {DATA_W{1'b0}} : din; // {DATA_W{1'b0}}: repeats 0 for all DATA_W bits.
endmodule
