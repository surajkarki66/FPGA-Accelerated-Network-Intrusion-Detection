// Minimal AXI4-Lite slave → FNN accelerator MMIO.
// Compatible with Zynq PS or a sim AXI BFM. 32-bit data, 8-bit addr decode.
`timescale 1ns / 1ps
`include "fnn_params.vh"

module axi4lite_slave #(
    parameter DATA_W = `FNN_DATA_W,
    parameter ACT_AW = `FNN_ACT_ADDR_W,
    parameter OUT_DIM = `FNN_OUTPUT_DIM
) (
    input  wire         ACLK,
    input  wire         ARESETN,

    // AXI4-Lite
    input  wire [7:0]   AWADDR,
    input  wire         AWVALID,
    output reg          AWREADY,
    input  wire [31:0]  WDATA,
    input  wire [3:0]   WSTRB,
    input  wire         WVALID,
    output reg          WREADY,
    output reg  [1:0]   BRESP,
    output reg          BVALID,
    input  wire         BREADY,
    input  wire [7:0]   ARADDR,
    input  wire         ARVALID,
    output reg          ARREADY,
    output reg  [31:0]  RDATA,
    output reg  [1:0]   RRESP,
    output reg          RVALID,
    input  wire         RREADY,

    // FNN
    output reg          fnn_start,
    input  wire         fnn_busy,
    input  wire         fnn_done,
    input  wire [31:0]  fnn_cycles,
    output reg          feat_we,
    output reg  [ACT_AW-1:0] feat_addr,
    output reg  signed [DATA_W-1:0] feat_wdata,
    input  wire [7:0]   pred,
    input  wire signed [OUT_DIM*DATA_W-1:0] scores_flat
);

    reg [7:0]  awaddr_r, araddr_r;
    reg [31:0] idx_r;
    reg        done_sticky;

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN)
            done_sticky <= 1'b0;
        else if (fnn_start)
            done_sticky <= 1'b0;
        else if (fnn_done)
            done_sticky <= 1'b1;
    end

    // Write channel
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            AWREADY <= 1'b0; WREADY <= 1'b0; BVALID <= 1'b0; BRESP <= 2'b00;
            awaddr_r <= 8'd0; fnn_start <= 1'b0; feat_we <= 1'b0;
            feat_addr <= {ACT_AW{1'b0}}; feat_wdata <= {DATA_W{1'b0}};
            idx_r <= 32'd0;
        end else begin
            fnn_start <= 1'b0;
            feat_we   <= 1'b0;

            if (!AWREADY && AWVALID)
                AWREADY <= 1'b1;
            else
                AWREADY <= 1'b0;

            if (!WREADY && WVALID)
                WREADY <= 1'b1;
            else
                WREADY <= 1'b0;

            if (AWREADY && AWVALID)
                awaddr_r <= AWADDR;

            if (WREADY && WVALID) begin
                case (awaddr_r)
                    `FNN_REG_CTRL: if (WDATA[0]) fnn_start <= 1'b1;
                    `FNN_REG_ADDR: idx_r <= WDATA;
                    `FNN_REG_DATA: begin
                        feat_we    <= 1'b1;
                        feat_addr  <= idx_r[ACT_AW-1:0];
                        feat_wdata <= WDATA[DATA_W-1:0];
                    end
                    default: ;
                endcase
                BVALID <= 1'b1;
                BRESP  <= 2'b00;
            end else if (BVALID && BREADY) begin
                BVALID <= 1'b0;
            end
        end
    end

    // Read channel
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            ARREADY <= 1'b0; RVALID <= 1'b0; RRESP <= 2'b00; RDATA <= 32'd0;
            araddr_r <= 8'd0;
        end else begin
            if (!ARREADY && ARVALID) begin
                ARREADY <= 1'b1;
                araddr_r <= ARADDR;
            end else
                ARREADY <= 1'b0;

            if (ARREADY && ARVALID) begin
                RVALID <= 1'b1;
                RRESP  <= 2'b00;
                case (ARADDR)
                    `FNN_REG_STATUS: RDATA <= {30'd0, fnn_busy, done_sticky};
                    `FNN_REG_PRED:   RDATA <= {24'd0, pred};
                    `FNN_REG_CYCLES: RDATA <= fnn_cycles;
                    `FNN_REG_DATA:   RDATA <= {{(32-DATA_W){scores_flat[idx_r*DATA_W + DATA_W-1]}},
                                               scores_flat[idx_r*DATA_W +: DATA_W]};
                    default:         RDATA <= 32'd0;
                endcase
            end else if (RVALID && RREADY) begin
                RVALID <= 1'b0;
            end
        end
    end

endmodule
