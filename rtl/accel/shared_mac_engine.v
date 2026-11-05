// NUM_PE parallel MAC lanes.
`timescale 1ns / 1ps
`include "fnn_params.vh"

module shared_mac_engine #(
    parameter DATA_W = `FNN_DATA_W,
    parameter NUM_PE = `FNN_NUM_PE
) (
    input  wire                         clk, // used by all MAC units
    input  wire                         rst_n, // active-low reset signal (activate when it is low)
    input  wire                         clear, // Controls clearing the accumulated value inside the MAC units.
    input  wire                         valid_in, // Indicates whether the incoming activation and corresponding weights are valid for processing.
    input  wire signed [DATA_W-1:0]     a, // a shared activation for all MAC units
    input  wire signed [NUM_PE*DATA_W-1:0] w_flat, // provides the weight values for all parallel MAC units in one wide bus.
    input  wire                         bias_add, // Controls when the bias value should be added to the accumulated result.
    input  wire signed [NUM_PE*DATA_W-1:0] bias_flat,
    input  wire                         finalize, // Indicates that the MAC calculation should be finalized
    input  wire [NUM_PE-1:0]            lane_enable, // Controls which MAC lanes are active.
    output wire signed [NUM_PE*DATA_W-1:0] y_flat,
    output wire [NUM_PE-1:0]            valid_out // Indicates which MAC lanes have produced valid outputs (each bit corresponds to one MAC unit 4'b1111)
);

    // Declares a generate variable:
    // A genvar is used during elaboration to create multiple hardware instances.
    // Unlike a normal integer used in procedural logic, a genvar is evaluated during hardware generation.
    genvar gi; 
    // Generate block
    generate
        for (gi = 0; gi < NUM_PE; gi = gi + 1) begin : pe  // This loop does not execute sequentially at runtime. It creates hardware instances during elaboration.
            wire signed [DATA_W-1:0] y_i; // output value of current MAC lane
            wire                    v_i; // Indicates whether the current MAC lane's output is valid

            // MAC unit instantiation
            mac_unit u_mac (
                .clk      (clk),
                .rst_n    (rst_n),
                .clear    (clear),
                .valid_in (valid_in & lane_enable[gi]),
                .a        (a),
                .w        (w_flat[gi*DATA_W +: DATA_W]),  // Verilog's indexed part-select operator: [starting_bit +: width]
                .bias_add (bias_add & lane_enable[gi]),
                .bias     (bias_flat[gi*DATA_W +: DATA_W]),
                .finalize (finalize & lane_enable[gi]),
                .y        (y_i),
                .valid_out(v_i)
            );
            // Assigning outputs to the flattened buses
            assign y_flat[gi*DATA_W +: DATA_W] = y_i; // Places the current MAC unit's output into its corresponding section of the flattened output bus.
            assign valid_out[gi] = v_i; // Connects the individual MAC unit's valid signal to the corresponding bit of the main valid_out bus.
        end
    endgenerate

endmodule
