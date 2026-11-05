// Signed INT8 MAC, INT32 accumulator, Q-rescale + saturation

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
    input  wire                     bias_add, // controls when the bias is added to the accumulator
    input  wire signed [DATA_W-1:0] bias,
    input  wire                     finalize,
    output reg  signed [DATA_W-1:0] y, // final INT8 result
    output reg                      valid_out // indicates that y contains a newly finalized result.
);

    reg  signed [ACC_W-1:0] acc; // accumulator declaration
    wire signed [2*DATA_W-1:0] prod     = a * w; // 16 bit prod register = w(8bit) x activation(8bit)

    // Because multiplication and accumulation can produce values much larger than an individual INT8 value. 
    // A wider accumulator reduces the risk of overflow while summing many products.
    // Extended multiplication result (32-bit)
    wire signed [ACC_W-1:0]    prod_ext = {{(ACC_W-2*DATA_W){prod[2*DATA_W-1]}}, prod}; // It uses sign extension, meaning it copies the sign bit into the additional upper bits
    // Bias is Q1.7; align to product domain Q2.14 before accumulate.
    wire signed [ACC_W-1:0]    bias_ext = {{(ACC_W-DATA_W){bias[DATA_W-1]}}, bias} <<< FRAC_BITS; // Since FRAC_BITS = 7, the value is shifted left by 7 positions: 16 bit
    wire signed [ACC_W-1:0]    shifted  = acc >>> FRAC_BITS; // convert the accumulator back to Q1.7.

    // INT8 bounds: After rescaling, the result might be outside the range representable by signed INT8
    wire signed [DATA_W-1:0] INT_MAX = {1'b0, {(DATA_W-1){1'b1}}}; // INT_MAX = 01111111 = 127
    wire signed [DATA_W-1:0] INT_MIN = {1'b1, {(DATA_W-1){1'b0}}}; // INT_MIN = 10000000 = -128

    // Extend the INT8 maximum and minimum values to the 32-bit accumulator width, allowing comparisons with shifted.
    wire signed [ACC_W-1:0]  max_ext =
        {{(ACC_W-DATA_W){INT_MAX[DATA_W-1]}}, INT_MAX};
    wire signed [ACC_W-1:0]  min_ext =
        {{(ACC_W-DATA_W){INT_MIN[DATA_W-1]}}, INT_MIN};

    // Saturation
    wire signed [DATA_W-1:0] sat_y =
        (shifted > max_ext) ? INT_MAX :
        (shifted < min_ext) ? INT_MIN :
        shifted[DATA_W-1:0];

    // Sequential logic
    always @(posedge clk or negedge rst_n) begin // On every rising edge of the clock. Immediately when rst_n goes low.
        if (!rst_n) begin // when reset is activated
            acc       <= {ACC_W{1'b0}};
            y         <= {DATA_W{1'b0}};
            valid_out <= 1'b0;
        end else begin // normal operation
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
