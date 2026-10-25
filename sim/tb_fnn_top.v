// Check RTL pred against software INT8 for every golden test sample.
`timescale 1ns / 1ps
`include "fnn_params.vh"
`include "sim/golden/golden_params.vh"

module tb_fnn_top;
    localparam DATA_W = `FNN_DATA_W;
    localparam IN_DIM = `FNN_INPUT_DIM;
    localparam ACT_AW = `FNN_ACT_ADDR_W;
    localparam OUT_DIM = `FNN_OUTPUT_DIM;
    localparam N_SAMPLES = `GOLDEN_N_SAMPLES;
    localparam FEAT_WORDS = `GOLDEN_FEAT_WORDS;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg start = 0;
    wire busy, done;
    wire [31:0] cycles;
    reg feat_we = 0;
    reg [ACT_AW-1:0] feat_addr = 0;
    reg signed [DATA_W-1:0] feat_wdata = 0;
    wire [7:0] pred;
    wire signed [OUT_DIM*DATA_W-1:0] scores;

    fnn_top #(
        .W_MEM_FILE("weights/generated/weights.mem"),
        .BIAS_MEM_FILE("weights/generated/biases.mem")
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .busy(busy), .done(done), .cycle_count(cycles),
        .feat_we(feat_we), .feat_addr(feat_addr), .feat_wdata(feat_wdata),
        .pred(pred), .scores_flat(scores)
    );

    // Flattened features: sample s uses [s*IN_DIM .. s*IN_DIM+IN_DIM-1]
    reg [7:0] features [0:FEAT_WORDS-1];
    reg [7:0] expected [0:N_SAMPLES-1];  // software INT8 pred
    reg [7:0] labels   [0:N_SAMPLES-1];  // true UNSW label

    // TB clock: #5 → 10 ns period → 100 MHz
    localparam real CLK_NS = 10.0;

    integer s, i;
    integer fails;
    integer correct_label;
    integer exp_pred, true_label;
    integer cyc;
    integer cyc_min, cyc_max;
    real    cyc_sum;
    real    lat_ns, lat_us, thr_mSPS;
    real    acc;

    initial begin
        // No VCD on full-set runs (file would be huge).
        $readmemh("sim/golden/features.mem", features);
        $readmemh("sim/golden/expected.mem", expected);
        $readmemh("sim/golden/labels.mem", labels);

        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        fails = 0;
        correct_label = 0;
        cyc_min = 32'h7fff_ffff;
        cyc_max = 0;
        cyc_sum = 0.0;

        $display("---- FNN latency sim  N=%0d  clk=%.0f ns (%.0f MHz) ----",
                 N_SAMPLES, CLK_NS, 1000.0 / CLK_NS);

        for (s = 0; s < N_SAMPLES; s = s + 1) begin
            for (i = 0; i < IN_DIM; i = i + 1) begin
                @(posedge clk);
                feat_we    <= 1'b1;
                feat_addr  <= i[ACT_AW-1:0];
                feat_wdata <= features[s*IN_DIM + i];
            end
            @(posedge clk);
            feat_we <= 1'b0;

            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            wait (done);
            @(posedge clk); // S_DONE → S_IDLE; pred held

            cyc = cycles;
            cyc_sum = cyc_sum + cyc;
            if (cyc < cyc_min) cyc_min = cyc;
            if (cyc > cyc_max) cyc_max = cyc;

            exp_pred   = expected[s];
            true_label = labels[s];
            if (pred === true_label[7:0])
                correct_label = correct_label + 1;

            if (pred !== exp_pred[7:0]) begin
                $display("FAIL sample %0d: pred=%0d expected=%0d label=%0d  latency=%0d cycles",
                         s, pred, exp_pred, true_label, cyc);
                fails = fails + 1;
                if (fails >= 10) begin
                    $display("Too many failures — aborting");
                    $fatal(1);
                end
            end

            if (s == 0)
                $display("sample 0: pred=%0d label=%0d  latency=%0d cycles (%.1f ns / %.3f us)",
                         pred, true_label, cyc, cyc * CLK_NS, cyc * CLK_NS / 1000.0);

            if ((s + 1) % 1000 == 0 || s + 1 == N_SAMPLES)
                $display("checked %0d / %0d  hw_vs_sw_fails=%0d  label_ok=%0d  last_latency=%0d cycles",
                         s + 1, N_SAMPLES, fails, correct_label, cyc);
        end

        lat_ns   = (cyc_sum / N_SAMPLES) * CLK_NS;
        lat_us   = lat_ns / 1000.0;
        thr_mSPS = 1000.0 / lat_ns; // million samples / s at this clock
        acc      = (100.0 * correct_label) / N_SAMPLES;

        $display("---- accuracy ----");
        $display("  RTL vs software INT8:  %0d / %0d match (fails=%0d)",
                 N_SAMPLES - fails, N_SAMPLES, fails);
        $display("  RTL vs true label:     %0d / %0d correct  accuracy=%.4f%%",
                 correct_label, N_SAMPLES, acc);

        $display("---- latency summary ----");
        $display("  cycles/sample:  min=%0d  avg=%.1f  max=%0d",
                 cyc_min, cyc_sum / N_SAMPLES, cyc_max);
        $display("  time/sample:    min=%.1f ns  avg=%.1f ns (%.3f us)  max=%.1f ns",
                 cyc_min * CLK_NS, lat_ns, lat_us, cyc_max * CLK_NS);
        $display("  throughput:     %.3f Msamples/s @ %.0f MHz (compute only)",
                 thr_mSPS, 1000.0 / CLK_NS);

        if (fails != 0) begin
            $display("FAIL: %0d / %0d HW vs SW mismatches", fails, N_SAMPLES);
            $fatal(1);
        end
        $display("PASS: all %0d samples match software INT8; label accuracy=%.4f%%",
                 N_SAMPLES, acc);
        $finish;
    end

    // Full UNSW test (~80k × ~500 cycles) needs a long wall-clock timeout
    initial begin
        #(64'd2_000_000_000_000);
        $display("TIMEOUT after %0d samples", s);
        $fatal(1);
    end
endmodule
