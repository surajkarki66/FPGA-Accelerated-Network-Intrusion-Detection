`timescale 1ns / 1ps
`include "fnn_params.vh"

module tb_mac_unit;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg clear, valid_in, bias_add, finalize;
    reg signed [`FNN_DATA_W-1:0] a, w, bias;
    wire signed [`FNN_DATA_W-1:0] y;
    wire valid_out;

    mac_unit dut (
        .clk(clk), .rst_n(rst_n),
        .clear(clear), .valid_in(valid_in), .a(a), .w(w),
        .bias_add(bias_add), .bias(bias), .finalize(finalize),
        .y(y), .valid_out(valid_out)
    );

    initial begin
        $dumpfile("sim/tb_mac_unit.vcd");
        $dumpvars(0, tb_mac_unit);
        clear = 0; valid_in = 0; bias_add = 0; finalize = 0;
        a = 0; w = 0; bias = 0;
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;

        // clear
        @(posedge clk); clear <= 1;
        @(posedge clk); clear <= 0;

        // 2 * 3  (Q1.7: 0x02 * 0x03) accumulate twice + bias 1
        @(posedge clk);
        a <= 8'sd2; w <= 8'sd3; valid_in <= 1;
        @(posedge clk);
        valid_in <= 1;
        @(posedge clk);
        valid_in <= 0;
        bias <= 8'sd1; bias_add <= 1;
        @(posedge clk);
        bias_add <= 0; finalize <= 1;
        @(posedge clk); // DUT samples finalize, pulses valid_out
        finalize <= 0;
        @(negedge clk); // sample mid-cycle while valid_out is still high
        if (!valid_out) $fatal(1, "no valid_out");
        // acc = 2*3 + 2*3 + (1<<7) = 6+6+128 = 140; >>7 = 1
        $display("y=%0d (expect 1)", y);
        if (y !== 8'sd1) $fatal(1, "mac mismatch");
        $display("PASS");
        $finish;
    end
endmodule
