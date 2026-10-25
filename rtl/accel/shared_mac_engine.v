// NUM_PE parallel MAC lanes. Same activation broadcast; per-lane weights/biases.
`timescale 1ns / 1ps
`include "fnn_params.vh"

module shared_mac_engine #(
    parameter DATA_W = `FNN_DATA_W,
    parameter NUM_PE = `FNN_NUM_PE
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         clear,
    input  wire                         valid_in,
    input  wire signed [DATA_W-1:0]     a,
    input  wire signed [NUM_PE*DATA_W-1:0] w_flat,
    input  wire                         bias_add,
    input  wire signed [NUM_PE*DATA_W-1:0] bias_flat,
    input  wire                         finalize,
    input  wire [NUM_PE-1:0]            lane_enable,
    output wire signed [NUM_PE*DATA_W-1:0] y_flat,
    output wire [NUM_PE-1:0]            valid_out
);

    genvar gi;
    generate
        for (gi = 0; gi < NUM_PE; gi = gi + 1) begin : pe
            wire signed [DATA_W-1:0] y_i;
            wire                    v_i;
            mac_unit u_mac (
                .clk      (clk),
                .rst_n    (rst_n),
                .clear    (clear),
                .valid_in (valid_in & lane_enable[gi]),
                .a        (a),
                .w        (w_flat[gi*DATA_W +: DATA_W]),
                .bias_add (bias_add & lane_enable[gi]),
                .bias     (bias_flat[gi*DATA_W +: DATA_W]),
                .finalize (finalize & lane_enable[gi]),
                .y        (y_i),
                .valid_out(v_i)
            );
            assign y_flat[gi*DATA_W +: DATA_W] = y_i;
            assign valid_out[gi] = v_i;
        end
    endgenerate

endmodule
