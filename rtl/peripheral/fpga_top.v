// Board-agnostic top: FNN + AXI slave.
// For non-SoC boards, replace AXI with UART/SPI host in a later revision.
`timescale 1ns / 1ps
`include "fnn_params.vh"

module fpga_top (
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Lite (connect to PS or soft host)
    input  wire [7:0]  AWADDR,
    input  wire        AWVALID,
    output wire        AWREADY,
    input  wire [31:0] WDATA,
    input  wire [3:0]  WSTRB,
    input  wire        WVALID,
    output wire        WREADY,
    output wire [1:0]  BRESP,
    output wire        BVALID,
    input  wire        BREADY,
    input  wire [7:0]  ARADDR,
    input  wire        ARVALID,
    output wire        ARREADY,
    output wire [31:0] RDATA,
    output wire [1:0]  RRESP,
    output wire        RVALID,
    input  wire        RREADY,

    // Optional debug
    output wire        dbg_busy,
    output wire        dbg_done,
    output wire [7:0]  dbg_pred
);

    wire        start, busy, done;
    wire [31:0] cycles;
    wire        feat_we;
    wire [`FNN_ACT_ADDR_W-1:0] feat_addr;
    wire signed [`FNN_DATA_W-1:0] feat_wdata;
    wire [7:0]  pred;
    wire signed [`FNN_OUTPUT_DIM*`FNN_DATA_W-1:0] scores;

    fnn_top u_fnn (
        .clk(clk), .rst_n(rst_n),
        .start(start), .busy(busy), .done(done), .cycle_count(cycles),
        .feat_we(feat_we), .feat_addr(feat_addr), .feat_wdata(feat_wdata),
        .pred(pred), .scores_flat(scores)
    );

    axi4lite_slave u_axi (
        .ACLK(clk), .ARESETN(rst_n),
        .AWADDR(AWADDR), .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA), .WSTRB(WSTRB), .WVALID(WVALID), .WREADY(WREADY),
        .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY),
        .ARADDR(ARADDR), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA(RDATA), .RRESP(RRESP), .RVALID(RVALID), .RREADY(RREADY),
        .fnn_start(start), .fnn_busy(busy), .fnn_done(done), .fnn_cycles(cycles),
        .feat_we(feat_we), .feat_addr(feat_addr), .feat_wdata(feat_wdata),
        .pred(pred), .scores_flat(scores)
    );

    assign dbg_busy = busy;
    assign dbg_done = done;
    assign dbg_pred = pred;

endmodule
