// =============================================================
// Testbench: tb_output_buffer
// Standalone unit test: drives sum_in_flat directly with known,
// synthetic staggered values (column c becomes valid at cycle
// LATENCY_OFFSET+c) rather than relying on a real systolic array,
// so this module is verified independently of its upstream.
// =============================================================

`timescale 1ns/1ps

module tb_output_buffer;

    localparam ACC_WIDTH = 32;
    localparam COLS = 8;
    localparam LATENCY_OFFSET = 5; // arbitrary, different from the real
                                    // pipeline's 9, specifically to prove
                                    // this module's correctness is general
                                    // and not coincidentally tied to one value
    localparam CNT_WIDTH = 6;

    reg clk, rst, capture_start;
    reg signed [COLS*ACC_WIDTH-1:0] sum_in_flat;
    wire busy, result_valid;
    wire signed [COLS*ACC_WIDTH-1:0] result_flat;

    integer j, t;
    integer errors = 0;
    reg signed [ACC_WIDTH-1:0] expected [0:COLS-1];

    output_buffer #(.ACC_WIDTH(ACC_WIDTH), .COLS(COLS), .LATENCY_OFFSET(LATENCY_OFFSET), .CNT_WIDTH(CNT_WIDTH)) dut (
        .clk(clk), .rst(rst),
        .capture_start(capture_start),
        .sum_in_flat(sum_in_flat),
        .busy(busy),
        .result_valid(result_valid),
        .result_flat(result_flat)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_output_buffer.vcd");
        $dumpvars(0, tb_output_buffer);

        clk = 0; rst = 1; capture_start = 0; sum_in_flat = 0;
        @(negedge clk); @(negedge clk);
        rst = 0;

        for (j = 0; j < COLS; j = j + 1)
            expected[j] = (j + 1) * 111; // distinct, easy-to-spot values

        capture_start = 1;
        @(negedge clk);
        capture_start = 0;

        // Drive sum_in_flat: column j should present its "final" value
        // starting from cycle LATENCY_OFFSET+j onward (mimicking a real
        // accumulating column feed, though the DUT only needs to sample
        // it at the right instant).
        for (t = 0; t < LATENCY_OFFSET + COLS + 5; t = t + 1) begin
            sum_in_flat = 0;
            for (j = 0; j < COLS; j = j + 1) begin
                if (t >= LATENCY_OFFSET + j)
                    sum_in_flat[(j+1)*ACC_WIDTH-1 -: ACC_WIDTH] = expected[j];
            end
            @(negedge clk);
            if (result_valid) begin
                $display("[INFO] result_valid pulsed at t=%0d", t);
                for (j = 0; j < COLS; j = j + 1) begin
                    begin : chk
                        reg signed [ACC_WIDTH-1:0] actual;
                        actual = result_flat[(j+1)*ACC_WIDTH-1 -: ACC_WIDTH];
                        if (actual !== expected[j]) begin
                            $display("[FAIL] result[%0d]: expected=%0d got=%0d", j, expected[j], actual);
                            errors = errors + 1;
                        end else begin
                            $display("[PASS] result[%0d] = %0d", j, actual);
                        end
                    end
                end
            end
        end

        // busy should be low after capture completes
        if (busy !== 1'b0) begin
            $display("[FAIL] busy should be 0 after capture completes, got %0d", busy);
            errors = errors + 1;
        end else begin
            $display("[PASS] busy=0 after capture completes");
        end

        $display("----------------------------------------");
        if (errors == 0)
            $display("ALL OUTPUT_BUFFER UNIT TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);
        $display("----------------------------------------");

        $finish;
    end

endmodule
