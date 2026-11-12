// Fully-connected layer scheduler: time-multiplexes up to FNN_MAX_LAYERS on a shared PE engine.

`timescale 1ns / 1ps
`include "fnn_params.vh"

module layer_controller #(
    parameter DATA_W    = `FNN_DATA_W,
    parameter NUM_PE    = `FNN_NUM_PE,
    parameter NUM_FC    = `FNN_NUM_FC,
    parameter OUT_DIM   = `FNN_OUTPUT_DIM,
    parameter BINARY    = `FNN_BINARY_OUT,
    parameter ACT_AW    = `FNN_ACT_ADDR_W,
    parameter W_AW      = `FNN_W_ADDR_W
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start, // Starts neural-network inference
    output reg                          busy, // Indicates inference is running
    output reg                          done,
    output reg  [31:0]                  cycle_count,

    output reg                          a_we, // enables writing
    output reg  [ACT_AW-1:0]            a_waddr,
    output reg  signed [DATA_W-1:0]     a_wdata,
    output reg  [ACT_AW-1:0]            a_raddr,
    input  wire signed [DATA_W-1:0]     a_rdata,

    output reg                          b_we,
    output reg  [ACT_AW-1:0]            b_waddr,
    output reg  signed [DATA_W-1:0]     b_wdata,
    output reg  [ACT_AW-1:0]            b_raddr,
    input  wire signed [DATA_W-1:0]     b_rdata,

    // Host interface: These signals allow an external host, such as a processor, to load the input features into activation memory A.
    input  wire                         host_we,
    input  wire [ACT_AW-1:0]            host_waddr,
    input  wire signed [DATA_W-1:0]     host_wdata,

    // Weight and bias memory interface
    output reg  [W_AW-1:0]              w_addr,
    input  wire signed [DATA_W-1:0]     w_rdata,
    output reg  [W_AW-1:0]              bias_addr,
    input  wire signed [DATA_W-1:0]     bias_rdata,

    // Shared MAC engine interface
    output reg                          eng_clear,
    output reg                          eng_valid,
    output reg  signed [DATA_W-1:0]     eng_a,
    output reg  signed [NUM_PE*DATA_W-1:0] eng_w_flat,
    output reg                          eng_bias_add,
    output reg  signed [NUM_PE*DATA_W-1:0] eng_bias_flat,
    output reg                          eng_finalize,
    output reg  [NUM_PE-1:0]            eng_lane_en, // Enables or disables individual PEs
    input  wire signed [NUM_PE*DATA_W-1:0] eng_y_flat,
    input  wire [NUM_PE-1:0]            eng_valid_out,

    output reg  signed [OUT_DIM*DATA_W-1:0] scores_flat,
    output reg  [7:0]                   pred
);

    // Sync-RAM reads need: REQ (drive addr) → WAIT (mem samples) → CAP (use dout)
    // Finite State Machine (FSM)
    // Each state performs a particular task.
    localparam S_IDLE     = 5'd0; // Waits for inference to start
    localparam S_INIT     = 5'd1; // Initializes a new group of output neurons
    localparam S_ACT_REQ  = 5'd2; // Requests an activation from memory
    localparam S_ACT_WAIT = 5'd3; // Waits for synchronous memory read
    localparam S_ACT_CAP  = 5'd4; // Captures the activation
    localparam S_W_REQ    = 5'd5; // Requests a weight
    localparam S_W_WAIT   = 5'd6; // Waits for weight memory
    localparam S_W_CAP    = 5'd7; // Captures the weight
    localparam S_MAC      = 5'd8; // Sends activation and weights to the MAC engine
    localparam S_B_REQ    = 5'd9; // Requests a bias
    localparam S_B_WAIT   = 5'd10; // Waits for bias memory
    localparam S_B_CAP    = 5'd11; // Captures the bias
    localparam S_BIAS     = 5'd12; // Triggers bias addition
    localparam S_FINAL    = 5'd13; // Triggers MAC finalization
    localparam S_WAIT_Y   = 5'd14; // Waits for valid MAC outputs
    localparam S_WRITE    = 5'd15; // Writes neuron outputs to activation memory
    localparam S_ADVANCE  = 5'd16; // Advances to another PE batch or layer
    localparam S_DECIDE   = 5'd17; // Determines the predicted class
    localparam S_DONE     = 5'd18; // Marks inference as complete

    localparam PE_W = (NUM_PE <= 1) ? 1 : $clog2(NUM_PE); // determines how many bits are required to address an individual PE.

    // internal register
    reg [4:0]  state; // Current FSM state
    reg [3:0]  layer; // Current fully connected layer number
    reg        src_is_a; // Selects activation memory A or B as the input
    reg        use_relu; // Determines whether ReLU is enabled
    reg [15:0] in_dim, out_dim;
    reg [W_AW-1:0] w_base, b_base;
    reg [15:0] out_base, in_idx;
    reg [PE_W-1:0] pe_i, wr_i;
    reg [NUM_PE-1:0] lanes; // Indicates which PEs are active
    reg signed [DATA_W-1:0] act_hold; // Temporarily stores the activation read from memory

    wire [7:0] arg_idx;
    wire signed [DATA_W-1:0] arg_max_unused;

    generate
        if (BINARY == 0) begin : g_argmax // Binary classification
            argmax #(.DATA_W(DATA_W), .NUM(OUT_DIM), .IDX_W(8)) u_argmax (
                .scores_flat(scores_flat),
                .index(arg_idx),
                .max_val(arg_max_unused)
            );
        end else begin : g_no_argmax // Multi-class classification
            assign arg_idx = 8'd0;
            assign arg_max_unused = {DATA_W{1'b0}};
        end
    endgenerate

    // ReLU: This extracts the output of the currently selected PE from eng_y_flat and passes it through the ReLU module.
    wire signed [DATA_W-1:0] wr_raw = eng_y_flat[wr_i*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] wr_relu;
    relu #(.DATA_W(DATA_W)) u_wr_relu (
        .din(wr_raw),
        .enable(use_relu),
        .dout(wr_relu)
    );

    // This function determines which PEs should be active for the current batch.
    // It allows the accelerator to handle layers whose output dimensions are not divisible by the number of PEs.
    function [NUM_PE-1:0] make_lanes;
        input [15:0] base;
        input [15:0] total;
        integer li;
        begin
            make_lanes = {NUM_PE{1'b0}};
            for (li = 0; li < NUM_PE; li = li + 1)
                if ((base + li[15:0]) < total)
                    make_lanes[li] = 1'b1;
        end
    endfunction

    // This task loads the geometry and memory addresses for a particular fully connected layer
    // Uses <= because this task is only called from the clocked always block
    task automatic set_layer_geom;
        input [3:0] L; // layer number (e.g FC1=0, FC2=1, etc)
        begin
            case (L)
                4'd0: begin
                    in_dim  <= `FNN_L0_IN;
                    out_dim <= `FNN_L0_OUT;
                    w_base  <= `FNN_W_BASE_0;
                    b_base  <= `FNN_B_BASE_0;
                end
                4'd1: begin
                    in_dim  <= `FNN_L1_IN;
                    out_dim <= `FNN_L1_OUT;
                    w_base  <= `FNN_W_BASE_1;
                    b_base  <= `FNN_B_BASE_1;
                end
                4'd2: begin
                    in_dim  <= `FNN_L2_IN;
                    out_dim <= `FNN_L2_OUT;
                    w_base  <= `FNN_W_BASE_2;
                    b_base  <= `FNN_B_BASE_2;
                end
                4'd3: begin
                    in_dim  <= `FNN_L3_IN;
                    out_dim <= `FNN_L3_OUT;
                    w_base  <= `FNN_W_BASE_3;
                    b_base  <= `FNN_B_BASE_3;
                end
                4'd4: begin
                    in_dim  <= `FNN_L4_IN;
                    out_dim <= `FNN_L4_OUT;
                    w_base  <= `FNN_W_BASE_4;
                    b_base  <= `FNN_B_BASE_4;
                end
                4'd5: begin
                    in_dim  <= `FNN_L5_IN;
                    out_dim <= `FNN_L5_OUT;
                    w_base  <= `FNN_W_BASE_5;
                    b_base  <= `FNN_B_BASE_5;
                end
                4'd6: begin
                    in_dim  <= `FNN_L6_IN;
                    out_dim <= `FNN_L6_OUT;
                    w_base  <= `FNN_W_BASE_6;
                    b_base  <= `FNN_B_BASE_6;
                end
                default: begin
                    in_dim  <= `FNN_L7_IN;
                    out_dim <= `FNN_L7_OUT;
                    w_base  <= `FNN_W_BASE_7;
                    b_base  <= `FNN_B_BASE_7;
                end
            endcase
            use_relu <= (L != NUM_FC - 1); // enables ReLU for all layers except the final fully connected layer
        end
    endtask

    // Main sequential logic: complete inference sequence
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // reset condition
            state <= S_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            cycle_count <= 32'd0;
            a_we <= 1'b0; b_we <= 1'b0;
            a_waddr <= {ACT_AW{1'b0}}; a_raddr <= {ACT_AW{1'b0}};
            b_waddr <= {ACT_AW{1'b0}}; b_raddr <= {ACT_AW{1'b0}};
            a_wdata <= {DATA_W{1'b0}}; b_wdata <= {DATA_W{1'b0}};
            w_addr <= {W_AW{1'b0}}; bias_addr <= {W_AW{1'b0}};
            eng_clear <= 1'b0; eng_valid <= 1'b0;
            eng_bias_add <= 1'b0; eng_finalize <= 1'b0;
            eng_lane_en <= {NUM_PE{1'b0}};
            eng_a <= {DATA_W{1'b0}};
            eng_w_flat <= {(NUM_PE*DATA_W){1'b0}};
            eng_bias_flat <= {(NUM_PE*DATA_W){1'b0}};
            scores_flat <= {(OUT_DIM*DATA_W){1'b0}};
            pred <= 8'd0;
            src_is_a <= 1'b1;
            layer <= 4'd0;
            use_relu <= 1'b1;
            in_dim <= 16'd0; out_dim <= 16'd0;
            w_base <= {W_AW{1'b0}}; b_base <= {W_AW{1'b0}};
            out_base <= 16'd0; in_idx <= 16'd0;
            pe_i <= {PE_W{1'b0}}; wr_i <= {PE_W{1'b0}};
            lanes <= {NUM_PE{1'b0}};
            act_hold <= {DATA_W{1'b0}};
        end else begin // default signal assignment: These signals are set to zero at the beginning of every normal clock cycle (because they are control pulses).
            a_we <= 1'b0;
            b_we <= 1'b0;
            eng_clear <= 1'b0;
            eng_valid <= 1'b0;
            eng_bias_add <= 1'b0;
            eng_finalize <= 1'b0;

            // Loading input features from the host
            if (!busy && host_we) begin
                a_we    <= 1'b1;
                a_waddr <= host_waddr;
                a_wdata <= host_wdata;
            end

            if (busy)
                cycle_count <= cycle_count + 1'b1; // cycle counter increment

            // state machine
            // The controller now executes the operation corresponding to its current state.
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        cycle_count <= 32'd0;
                        src_is_a <= 1'b1;
                        layer <= 4'd0;
                        out_base <= 16'd0;
                        set_layer_geom(4'd0);
                        state <= S_INIT;
                    end
                end

                S_INIT: begin // Initialize the PE batch
                    eng_clear   <= 1'b1;
                    lanes       <= make_lanes(out_base, out_dim);
                    eng_lane_en <= make_lanes(out_base, out_dim);
                    in_idx      <= 16'd0;
                    pe_i        <= {PE_W{1'b0}};
                    state       <= S_ACT_REQ;
                end

                S_ACT_REQ: begin // Read an activation
                    if (src_is_a) // the controller reads from activation memory A
                        a_raddr <= in_idx[ACT_AW-1:0];
                    else // otherwise it reads from activation memory B
                        b_raddr <= in_idx[ACT_AW-1:0];
                    state <= S_ACT_WAIT;
                end

                S_ACT_WAIT: state <= S_ACT_CAP; // activation memory uses synchronous reading. Therefore, the controller waits for the memory output to become available.

                S_ACT_CAP: begin // Capture the activation
                    act_hold <= src_is_a ? a_rdata : b_rdata;
                    pe_i <= {PE_W{1'b0}}; // resetting PE index
                    state <= S_W_REQ;
                end

                S_W_REQ: begin // Requests weights
                    if (lanes[pe_i])
                        w_addr <= (w_base + (out_base + pe_i) * in_dim + in_idx); // It calculates the memory address of the required weight
                    state <= S_W_WAIT;
                end

                S_W_WAIT: state <= S_W_CAP; // wait and capture weights

                S_W_CAP: begin // weights are collected into packed bus: eng_w_flat = [w3][w2][w1][w0]
                    if (lanes[pe_i])
                        eng_w_flat[pe_i*DATA_W +: DATA_W] <= w_rdata;
                    if ({1'b0, pe_i} + 1 < NUM_PE) begin
                        pe_i  <= pe_i + 1'b1;
                        state <= S_W_REQ;
                    end else
                        state <= S_MAC;
                end

                S_MAC: begin // Perform Multiply and Accumulate
                    eng_a     <= act_hold;
                    eng_valid <= 1'b1;
                    if (in_idx + 1'b1 < in_dim) begin // looking for more activation
                        in_idx <= in_idx + 1'b1;
                        state  <= S_ACT_REQ; // goes to reading activation
                    end else begin
                        pe_i  <= {PE_W{1'b0}};
                        state <= S_B_REQ;
                    end
                end

                S_B_REQ: begin // Request bias
                    if (lanes[pe_i])
                        bias_addr <= (b_base + out_base + pe_i);
                    state <= S_B_WAIT;
                end

                S_B_WAIT: state <= S_B_CAP;

                S_B_CAP: begin // Capture the each biases
                    if (lanes[pe_i])
                        eng_bias_flat[pe_i*DATA_W +: DATA_W] <= bias_rdata; // eng_bias_flat = [b3][b2][b1][b0]
                    if ({1'b0, pe_i} + 1 < NUM_PE) begin // look for another PE
                        pe_i  <= pe_i + 1'b1;
                        state <= S_B_REQ;
                    end else
                        state <= S_BIAS;
                end

                S_BIAS: begin
                    eng_bias_add <= 1'b1; // This asserts the bias-add control signal.
                    state <= S_FINAL; // Each MAC unit adds its own bias to its accumulator
                end

                S_FINAL: begin // Finalize the MAC result
                    eng_finalize <= 1'b1;
                    state <= S_WAIT_Y;
                end

                S_WAIT_Y: begin // Wait for the results
                    if (|eng_valid_out) begin // Reduction OR
                        wr_i  <= {PE_W{1'b0}};
                        state <= S_WRITE;
                    end
                end
                // This state writes the calculated neuron outputs into the destination activation memory.
                S_WRITE: begin // Write neuron outputs
                    if (lanes[wr_i]) begin
                        if (src_is_a) begin
                            b_we    <= 1'b1;
                            b_waddr <= out_base[ACT_AW-1:0] +
                                       {{(ACT_AW-PE_W){1'b0}}, wr_i};
                            b_wdata <= wr_relu;
                        end else begin
                            a_we    <= 1'b1;
                            a_waddr <= out_base[ACT_AW-1:0] +
                                       {{(ACT_AW-PE_W){1'b0}}, wr_i};
                            a_wdata <= wr_relu;
                        end
                        if (layer == NUM_FC - 1) // if it is the final layer
                            scores_flat[(out_base + {{(16-PE_W){1'b0}}, wr_i})*DATA_W +: DATA_W] <= wr_relu;
                    end
                    if ({1'b0, wr_i} + 1 < NUM_PE)
                        wr_i <= wr_i + 1'b1;
                    else
                        state <= S_ADVANCE;
                end

                S_ADVANCE: begin // Moving the next layer or batch
                    if (out_base + NUM_PE < out_dim) begin // checks whether there are more output neurons to calculate in the current layer.
                        out_base <= out_base + NUM_PE;
                        state    <= S_INIT;
                    end else if (layer + 1 < NUM_FC) begin
                        src_is_a <= ~src_is_a;
                        layer    <= layer + 1'b1;
                        out_base <= 16'd0;
                        set_layer_geom(layer + 1'b1);
                        state    <= S_INIT;
                    end else
                        state <= S_DECIDE;
                end

                S_DECIDE: begin // Classification
                    if (BINARY)
                        // score >= 0 → class 1, else class 0
                        pred <= {7'b0, ~scores_flat[DATA_W-1]}; // uses sign of the output score
                    else
                        pred <= arg_idx;
                    state <= S_DONE;
                end

                S_DONE: begin // Inference completion
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
