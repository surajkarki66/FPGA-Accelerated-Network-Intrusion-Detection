// Combinational tree argmax over OUTPUT_DIM signed scores.
`timescale 1ns / 1ps
`include "fnn_params.vh"

module argmax #(
    parameter DATA_W  = `FNN_DATA_W,
    parameter NUM     = `FNN_OUTPUT_DIM,
    parameter IDX_W   = 8
) (
    input  wire signed [NUM*DATA_W-1:0] scores_flat,
    output reg         [IDX_W-1:0]      index,
    output reg  signed [DATA_W-1:0]     max_val
);
    integer i;
    reg signed [DATA_W-1:0] s;

    always @(*) begin
        max_val = scores_flat[DATA_W-1:0];
        index   = {IDX_W{1'b0}};
        for (i = 1; i < NUM; i = i + 1) begin
            s = scores_flat[i*DATA_W +: DATA_W];
            if (s > max_val) begin
                max_val = s;
                index   = i[IDX_W-1:0];
            end
        end
    end
endmodule
