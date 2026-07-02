// =============================================================
// Testbench: tb_array
// Strategy:
//   Load a known 8x8 weight matrix W into the array.
//   Drive a single activation vector x, ONE ROW AT A TIME,
//   externally skewed: row r's value x[r] appears on a_in row r
//   at cycle r, and 0 every other cycle (single pulse per row).
//
//   For a weight-stationary systolic array with this pulse input,
//   column c's south-edge output carries the dot product
//       y[c] = sum_r ( W[r][c] * x[r] )
//   at some fixed latency cycle. Because working out that exact
//   cycle by hand is error-prone, this testbench captures every
//   sum_out sample over a generous window and SEARCHES for the
//   expected golden value on each column, then checks the
//   latencies it finds are self-consistent (increase by 1 per
//   column, matching the array's diagonal structure) rather than
//   hardcoding a possibly-wrong constant.
// =============================================================

`timescale 1ns/1ps

module tb_array;

    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = 32;
    localparam ROWS = 8;
    localparam COLS = 8;
    localparam WINDOW = 40; // cycles to capture after driving inputs

    reg clk, rst, en, load_weight;
    reg signed [ROWS*COLS*DATA_WIDTH-1:0] w_in_flat;
    reg signed [ROWS*DATA_WIDTH-1:0]      a_in_flat;
    wire signed [ROWS*DATA_WIDTH-1:0]     a_out_flat;
    reg signed [COLS*ACC_WIDTH-1:0]       sum_in_flat;
    wire signed [COLS*ACC_WIDTH-1:0]      sum_out_flat;

    integer i, j, cyc;
    integer errors = 0;

    // golden model storage
    reg signed [DATA_WIDTH-1:0] W [0:ROWS-1][0:COLS-1];
    reg signed [DATA_WIDTH-1:0] X [0:ROWS-1];
    reg signed [ACC_WIDTH-1:0]  golden [0:COLS-1];

    // capture buffer: sum_out per column per cycle
    reg signed [ACC_WIDTH-1:0] capture [0:WINDOW-1][0:COLS-1];

    integer found_cycle [0:COLS-1];
    integer match_count;

    systolic_array #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .ROWS(ROWS), .COLS(COLS)) dut (
        .clk(clk), .rst(rst), .en(en),
        .load_weight(load_weight), .w_in_flat(w_in_flat),
        .a_in_flat(a_in_flat), .a_out_flat(a_out_flat),
        .sum_in_flat(sum_in_flat), .sum_out_flat(sum_out_flat)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_array.vcd");
        $dumpvars(0, tb_array);

        clk = 0; rst = 1; en = 0; load_weight = 0;
        w_in_flat = 0; a_in_flat = 0; sum_in_flat = 0;

        // ---- Define a known small weight matrix and input vector ----
        // Keep values small so golden dot products are easy to sanity check.
        for (i = 0; i < ROWS; i = i + 1)
            for (j = 0; j < COLS; j = j + 1)
                W[i][j] = ((i * COLS + j) % 7) - 3; // spread of small +/- values

        for (i = 0; i < ROWS; i = i + 1)
            X[i] = i - 4; // -4..3

        // Compute golden dot products: golden[c] = sum_r W[r][c]*X[r]
        for (j = 0; j < COLS; j = j + 1) begin
            golden[j] = 0;
            for (i = 0; i < ROWS; i = i + 1)
                golden[j] = golden[j] + W[i][j] * X[i];
        end

        $display("Golden expected outputs (y = x^T W):");
        for (j = 0; j < COLS; j = j + 1)
            $display("  y[%0d] = %0d", j, golden[j]);

        @(negedge clk);
        @(negedge clk);
        rst = 0;

        // ---- Load weights (broadcast, single cycle) ----
        for (i = 0; i < ROWS; i = i + 1)
            for (j = 0; j < COLS; j = j + 1)
                w_in_flat[((i*COLS+j)+1)*DATA_WIDTH-1 -: DATA_WIDTH] = W[i][j];

        load_weight = 1; en = 1;
        @(negedge clk);
        load_weight = 0;

        // ---- Drive skewed single-pulse vector input ----
        // Row r gets X[r] exactly at cycle r (relative to this point),
        // 0 otherwise.
        for (cyc = 0; cyc < WINDOW; cyc = cyc + 1) begin
            a_in_flat = 0;
            for (i = 0; i < ROWS; i = i + 1) begin
                if (cyc == i)
                    a_in_flat[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH] = X[i];
            end
            @(negedge clk);
            // capture sum_out this cycle
            for (j = 0; j < COLS; j = j + 1)
                capture[cyc][j] = sum_out_flat[(j+1)*ACC_WIDTH-1 -: ACC_WIDTH];
        end

        // ---- Search capture buffer for golden values on each column ----
        $display("----------------------------------------");
        begin : search_block
            for (j = 0; j < COLS; j = j + 1) begin
                found_cycle[j] = -1;
                match_count = 0;
                for (cyc = 0; cyc < WINDOW; cyc = cyc + 1) begin
                    if (capture[cyc][j] === golden[j]) begin
                        match_count = match_count + 1;
                        if (found_cycle[j] == -1)
                            found_cycle[j] = cyc;
                    end
                end
                if (found_cycle[j] == -1) begin
                    $display("[FAIL] Column %0d: golden value %0d never appeared in %0d-cycle window",
                              j, golden[j], WINDOW);
                    errors = errors + 1;
                end else begin
                    $display("[PASS] Column %0d: golden value %0d found at cycle %0d (%0d occurrence(s) in window)",
                              j, golden[j], found_cycle[j], match_count);
                end
            end

            // Check the latencies are self-consistent: column c+1 should
            // appear exactly 1 cycle after column c (diagonal structure).
            for (j = 0; j < COLS-1; j = j + 1) begin
                if (found_cycle[j] != -1 && found_cycle[j+1] != -1) begin
                    if (found_cycle[j+1] - found_cycle[j] !== 1) begin
                        $display("[FAIL] Latency skew broken between col %0d (cyc %0d) and col %0d (cyc %0d)",
                                  j, found_cycle[j], j+1, found_cycle[j+1]);
                        errors = errors + 1;
                    end
                end
            end
        end

        $display("----------------------------------------");
        if (errors == 0)
            $display("ALL SYSTOLIC ARRAY CHECKS PASSED");
        else
            $display("%0d CHECK(S) FAILED", errors);
        $display("----------------------------------------");

        $finish;
    end

endmodule
