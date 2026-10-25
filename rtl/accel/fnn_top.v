// Core FNN accelerator: memories + shared PE engine + N-layer FSM.
`timescale 1ns / 1ps
`include "fnn_params.vh"

module fnn_top #(
    parameter DATA_W    = `FNN_DATA_W,
    parameter NUM_PE    = `FNN_NUM_PE,
    parameter OUT_DIM   = `FNN_OUTPUT_DIM,
    parameter ACT_AW    = `FNN_ACT_ADDR_W,
    parameter W_AW      = `FNN_W_ADDR_W,
    parameter W_MEM_FILE    = "weights/generated/weights.mem",
    parameter BIAS_MEM_FILE = "weights/generated/biases.mem"
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    output wire                     busy,
    output wire                     done,
    output wire [31:0]              cycle_count,

    input  wire                     feat_we,
    input  wire [ACT_AW-1:0]        feat_addr,
    input  wire signed [DATA_W-1:0] feat_wdata,

    output wire [7:0]               pred,
    output wire signed [OUT_DIM*DATA_W-1:0] scores_flat
);

    wire                 a_we, b_we;
    wire [ACT_AW-1:0]    a_waddr, a_raddr, b_waddr, b_raddr;
    wire signed [DATA_W-1:0] a_wdata, a_rdata, b_wdata, b_rdata;

    act_mem #(.DATA_W(DATA_W), .DEPTH(`FNN_MAX_WIDTH), .ADDR_W(ACT_AW)) u_act_a (
        .clk(clk), .we(a_we), .waddr(a_waddr), .wdata(a_wdata),
        .raddr(a_raddr), .rdata(a_rdata)
    );
    act_mem #(.DATA_W(DATA_W), .DEPTH(`FNN_MAX_WIDTH), .ADDR_W(ACT_AW)) u_act_b (
        .clk(clk), .we(b_we), .waddr(b_waddr), .wdata(b_wdata),
        .raddr(b_raddr), .rdata(b_rdata)
    );

    wire [W_AW-1:0] w_addr, bias_addr;
    wire signed [DATA_W-1:0] w_rdata, bias_rdata;

    // Depths come from fnn_params.vh (exact model size — no empty headroom).
    weight_mem #(.DATA_W(DATA_W), .DEPTH(`FNN_W_DEPTH), .ADDR_W(W_AW),
                 .MEM_FILE(W_MEM_FILE)) u_wmem (
        .clk(clk), .addr(w_addr), .dout(w_rdata)
    );
    weight_mem #(.DATA_W(DATA_W), .DEPTH(`FNN_B_DEPTH), .ADDR_W(W_AW),
                 .MEM_FILE(BIAS_MEM_FILE)) u_bmem (
        .clk(clk), .addr(bias_addr), .dout(bias_rdata)
    );

    wire                 eng_clear, eng_valid, eng_bias_add, eng_finalize;
    wire signed [DATA_W-1:0] eng_a;
    wire signed [NUM_PE*DATA_W-1:0] eng_w_flat, eng_bias_flat, eng_y_flat;
    wire [NUM_PE-1:0]    eng_lane_en, eng_valid_out;

    shared_mac_engine #(.DATA_W(DATA_W), .NUM_PE(NUM_PE)) u_engine (
        .clk(clk), .rst_n(rst_n),
        .clear(eng_clear), .valid_in(eng_valid), .a(eng_a), .w_flat(eng_w_flat),
        .bias_add(eng_bias_add), .bias_flat(eng_bias_flat),
        .finalize(eng_finalize), .lane_enable(eng_lane_en),
        .y_flat(eng_y_flat), .valid_out(eng_valid_out)
    );

    layer_controller #(
        .DATA_W(DATA_W), .NUM_PE(NUM_PE),
        .NUM_FC(`FNN_NUM_FC), .OUT_DIM(OUT_DIM),
        .BINARY(`FNN_BINARY_OUT),
        .ACT_AW(ACT_AW), .W_AW(W_AW)
    ) u_ctrl (
        .clk(clk), .rst_n(rst_n), .start(start),
        .busy(busy), .done(done), .cycle_count(cycle_count),
        .a_we(a_we), .a_waddr(a_waddr), .a_wdata(a_wdata),
        .a_raddr(a_raddr), .a_rdata(a_rdata),
        .b_we(b_we), .b_waddr(b_waddr), .b_wdata(b_wdata),
        .b_raddr(b_raddr), .b_rdata(b_rdata),
        .host_we(feat_we), .host_waddr(feat_addr), .host_wdata(feat_wdata),
        .w_addr(w_addr), .w_rdata(w_rdata),
        .bias_addr(bias_addr), .bias_rdata(bias_rdata),
        .eng_clear(eng_clear), .eng_valid(eng_valid), .eng_a(eng_a),
        .eng_w_flat(eng_w_flat), .eng_bias_add(eng_bias_add),
        .eng_bias_flat(eng_bias_flat), .eng_finalize(eng_finalize),
        .eng_lane_en(eng_lane_en), .eng_y_flat(eng_y_flat),
        .eng_valid_out(eng_valid_out),
        .scores_flat(scores_flat), .pred(pred)
    );

endmodule
