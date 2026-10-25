// Signed INT8 MAC, INT32 accumulator, Q-rescale + saturate on finalize.
// Contract: do not assert finalize in the same cycle as valid_in / bias_add.
`timescale 1ns / 1ps
`include "fnn_params.vh"

module mac_unit #(
    parameter DATA_W    = `FNN_DATA_W,
    parameter ACC_W     = `FNN_ACC_W,
    parameter FRAC_BITS = `FNN_FRAC_BITS
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,
    input  wire                     valid_in,
    input  wire signed [DATA_W-1:0] a,
    input  wire signed [DATA_W-1:0] w,
    input  wire                     bias_add,
    input  wire signed [DATA_W-1:0] bias,
    input  wire                     finalize,
    output reg  signed [DATA_W-1:0] y,
    output reg                      valid_out
);

    reg  signed [ACC_W-1:0] acc;
    wire signed [2*DATA_W-1:0] prod     = a * w;
    wire signed [ACC_W-1:0]    prod_ext = {{(ACC_W-2*DATA_W){prod[2*DATA_W-1]}}, prod};
    // Bias is Q1.7; align to product domain Q2.14 before accumulate.
    wire signed [ACC_W-1:0]    bias_ext = {{(ACC_W-DATA_W){bias[DATA_W-1]}}, bias} <<< FRAC_BITS;
    wire signed [ACC_W-1:0]    shifted  = acc >>> FRAC_BITS;

    // INT8 bounds (concat is unsigned in Verilog — keep signed wires for compares)
    wire signed [DATA_W-1:0] INT_MAX = {1'b0, {(DATA_W-1){1'b1}}};
    wire signed [DATA_W-1:0] INT_MIN = {1'b1, {(DATA_W-1){1'b0}}};
    wire signed [ACC_W-1:0]  max_ext =
        {{(ACC_W-DATA_W){INT_MAX[DATA_W-1]}}, INT_MAX};
    wire signed [ACC_W-1:0]  min_ext =
        {{(ACC_W-DATA_W){INT_MIN[DATA_W-1]}}, INT_MIN};

    wire signed [DATA_W-1:0] sat_y =
        (shifted > max_ext) ? INT_MAX :
        (shifted < min_ext) ? INT_MIN :
        shifted[DATA_W-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc       <= {ACC_W{1'b0}};
            y         <= {DATA_W{1'b0}};
            valid_out <= 1'b0;
        end else begin
            valid_out <= 1'b0;

            if (clear)
                acc <= {ACC_W{1'b0}};
            else if (valid_in && bias_add)
                acc <= acc + prod_ext + bias_ext;
            else if (valid_in)
                acc <= acc + prod_ext;
            else if (bias_add)
                acc <= acc + bias_ext;

            if (finalize) begin
                y         <= sat_y;
                valid_out <= 1'b1;
            end
        end
    end

endmodule
