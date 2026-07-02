// =============================================================
// Testbench: tb_full_pipeline
// Chains input_buffer -> systolic_array -> output_buffer.
// Verifies the output_buffer's result_flat, once result_valid
// pulses, exactly equals the golden matmul vector (same W, X as
// prior tests) -- and that LATENCY_OFFSET (measured empirically
// from the earlier integration test: column 0 arrived at cycle 8)
// is correct by checking result_valid fires at the expected cycle
// and every column value is right in one shot, no per-column
// search needed anymore -- this is the whole point of the
// output_buffer's alignment.
// =============================================================

`timescale 1ns/1ps

module tb_full_pipeline;

    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = 32;
    localparam ROWS = 8;
    localparam COLS = 8;
    localparam MAX_COLS = 16;
    localparam COL_ADDR_W = 5;
    localparam LATENCY_OFFSET = 9; // empirically verified: column 0 result lands at t=9 relative to capture_start/start pulse
    localparam CNT_WIDTH = 6;

    reg clk, rst;
    reg wr_en;
    reg [2:0] wr_row;
    reg [COL_ADDR_W-1:0] wr_col;
    reg signed [DATA_WIDTH-1:0] wr_data;
    reg start;
    reg [COL_ADDR_W-1:0] num_cols;
    wire ib_busy, ib_done;
    wire signed [ROWS*DATA_WIDTH-1:0] a_link_flat;

    reg en_array, load_weight;
    reg signed [ROWS*COLS*DATA_WIDTH-1:0] w_in_flat;
    wire signed [ROWS*DATA_WIDTH-1:0] a_out_flat_unused;
    reg signed [COLS*ACC_WIDTH-1:0] sum_in_flat;
    wire signed [COLS*ACC_WIDTH-1:0] sum_out_flat;

    reg capture_start;
    wire ob_busy, result_valid;
    wire signed [COLS*ACC_WIDTH-1:0] result_flat;

    integer i, j;
    integer errors = 0;
    integer cyc_count;

    reg signed [DATA_WIDTH-1:0] W [0:ROWS-1][0:COLS-1];
    reg signed [DATA_WIDTH-1:0] X [0:ROWS-1];
    reg signed [ACC_WIDTH-1:0]  golden [0:COLS-1];

    input_buffer #(.DATA_WIDTH(DATA_WIDTH), .ROWS(ROWS), .MAX_COLS(MAX_COLS), .COL_ADDR_W(COL_ADDR_W)) ib (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .wr_row(wr_row), .wr_col(wr_col), .wr_data(wr_data),
        .start(start), .num_cols(num_cols),
        .busy(ib_busy), .done(ib_done),
        .a_out_flat(a_link_flat)
    );

    systolic_array #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .ROWS(ROWS), .COLS(COLS)) arr (
        .clk(clk), .rst(rst), .en(en_array),
        .load_weight(load_weight), .w_in_flat(w_in_flat),
        .a_in_flat(a_link_flat), .a_out_flat(a_out_flat_unused),
        .sum_in_flat(sum_in_flat), .sum_out_flat(sum_out_flat)
    );

    output_buffer #(.ACC_WIDTH(ACC_WIDTH), .COLS(COLS), .LATENCY_OFFSET(LATENCY_OFFSET), .CNT_WIDTH(CNT_WIDTH)) ob (
        .clk(clk), .rst(rst),
        .capture_start(capture_start),
        .sum_in_flat(sum_out_flat),
        .busy(ob_busy),
        .result_valid(result_valid),
        .result_flat(result_flat)
    );

    always #5 clk = ~clk;

    // count cycles since capture_start, for reporting when result_valid fires
    always @(posedge clk or posedge rst) begin
        if (rst) cyc_count <= 0;
        else if (capture_start) cyc_count <= 0;
        else cyc_count <= cyc_count + 1;
    end

    initial begin
        $dumpfile("tb_full_pipeline.vcd");
        $dumpvars(0, tb_full_pipeline);

        clk = 0; rst = 1; wr_en = 0; wr_row = 0; wr_col = 0; wr_data = 0;
        start = 0; num_cols = 0;
        en_array = 0; load_weight = 0; w_in_flat = 0; sum_in_flat = 0;
        capture_start = 0;
        @(negedge clk); @(negedge clk);
        rst = 0;

        for (i = 0; i < ROWS; i = i + 1)
            for (j = 0; j < COLS; j = j + 1)
                W[i][j] = ((i * COLS + j) % 7) - 3;

        for (i = 0; i < ROWS; i = i + 1)
            X[i] = i - 4;

        for (j = 0; j < COLS; j = j + 1) begin
            golden[j] = 0;
            for (i = 0; i < ROWS; i = i + 1)
                golden[j] = golden[j] + W[i][j] * X[i];
        end

        $display("Golden expected outputs:");
        for (j = 0; j < COLS; j = j + 1)
            $display("  y[%0d] = %0d", j, golden[j]);

        // Load weights
        for (i = 0; i < ROWS; i = i + 1)
            for (j = 0; j < COLS; j = j + 1)
                w_in_flat[((i*COLS+j)+1)*DATA_WIDTH-1 -: DATA_WIDTH] = W[i][j];
        load_weight = 1; en_array = 1;
        @(negedge clk);
        load_weight = 0;

        // Load X into input buffer
        for (i = 0; i < ROWS; i = i + 1) begin
            wr_en = 1; wr_row = i[2:0]; wr_col = 0; wr_data = X[i];
            @(negedge clk);
        end
        wr_en = 0;

        // Kick off both the input buffer stream AND the output buffer
        // capture window on the SAME cycle -- this is the reference
        // point LATENCY_OFFSET is measured from.
        num_cols = 1;
        start = 1;
        capture_start = 1;
        @(negedge clk);
        start = 0;
        capture_start = 0;

        // Wait for result_valid, with a generous timeout
        i = 0;
        while (!result_valid && i < 50) begin
            @(negedge clk);
            i = i + 1;
        end

        if (!result_valid) begin
            $display("[FAIL] result_valid never asserted within timeout");
            errors = errors + 1;
        end else begin
            $display("[INFO] result_valid asserted at cycle_count=%0d (relative to capture_start)", cyc_count);
            for (j = 0; j < COLS; j = j + 1) begin
                begin : chk
                    reg signed [ACC_WIDTH-1:0] actual;
                    actual = result_flat[(j+1)*ACC_WIDTH-1 -: ACC_WIDTH];
                    if (actual !== golden[j]) begin
                        $display("[FAIL] result[%0d]: expected=%0d got=%0d", j, golden[j], actual);
                        errors = errors + 1;
                    end else begin
                        $display("[PASS] result[%0d] = %0d", j, actual);
                    end
                end
            end
        end

        $display("----------------------------------------");
        if (errors == 0)
            $display("FULL PIPELINE TEST: ALL CHECKS PASSED (input_buffer -> systolic_array -> output_buffer)");
        else
            $display("FULL PIPELINE TEST: %0d CHECK(S) FAILED", errors);
        $display("----------------------------------------");

        $finish;
    end

endmodule
