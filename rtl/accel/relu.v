`timescale 1ns / 1ps
`include "fnn_params.vh"

module relu #(
    parameter DATA_W = `FNN_DATA_W
) (
    input  wire signed [DATA_W-1:0] din,
    input  wire                     enable,  // 0 = bypass (output layer)
    output wire signed [DATA_W-1:0] dout
);
    assign dout = (enable && din[DATA_W-1]) ? {DATA_W{1'b0}} : din;
endmodule
