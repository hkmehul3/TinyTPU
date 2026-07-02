// =============================================================
// Testbench: tb_pe
// Verifies:
//   1. Reset clears weight, a_out, sum_out
//   2. load_weight latches w_in and holds it after load_weight=0
//   3. Activation pass-through: a_out(t+1) == a_in(t)
//   4. sum_out(t+1) == sum_in(t) + weight * a_in(t)
//   5. en=0 stalls the datapath (a_out/sum_out hold)
//   6. Negative weight/activation combos (signed correctness)
// =============================================================

`timescale 1ns/1ps

module tb_pe;

    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = 32;

    reg                          clk;
    reg                          rst;
    reg                          en;
    reg                          load_weight;
    reg  signed [DATA_WIDTH-1:0] w_in;
    reg  signed [DATA_WIDTH-1:0] a_in;
    wire signed [DATA_WIDTH-1:0] a_out;
    reg  signed [ACC_WIDTH-1:0]  sum_in;
    wire signed [ACC_WIDTH-1:0]  sum_out;

    integer errors = 0;
    integer test_num = 0;

    pe #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) dut (
        .clk(clk), .rst(rst), .en(en),
        .load_weight(load_weight), .w_in(w_in),
        .a_in(a_in), .a_out(a_out),
        .sum_in(sum_in), .sum_out(sum_out)
    );

    always #5 clk = ~clk;

    task check_ao(input signed [DATA_WIDTH-1:0] expected, input [127:0] name);
        begin
            test_num = test_num + 1;
            if (a_out !== expected) begin
                $display("[FAIL] Test %0d (%0s): a_out expected=%0d got=%0d", test_num, name, expected, a_out);
                errors = errors + 1;
            end else
                $display("[PASS] Test %0d (%0s): a_out=%0d", test_num, name, a_out);
        end
    endtask

    task check_so(input signed [ACC_WIDTH-1:0] expected, input [127:0] name);
        begin
            test_num = test_num + 1;
            if (sum_out !== expected) begin
                $display("[FAIL] Test %0d (%0s): sum_out expected=%0d got=%0d", test_num, name, expected, sum_out);
                errors = errors + 1;
            end else
                $display("[PASS] Test %0d (%0s): sum_out=%0d", test_num, name, sum_out);
        end
    endtask

    initial begin
        $dumpfile("tb_pe.vcd");
        $dumpvars(0, tb_pe);

        clk = 0; rst = 1; en = 0; load_weight = 0;
        w_in = 0; a_in = 0; sum_in = 0;
        @(negedge clk);
        @(negedge clk);

        // Test 1-2: reset clears everything
        check_ao(0, "reset a_out");
        check_so(0, "reset sum_out");

        // Load weight = 5, no en, so a_out/sum_out shouldn't advance
        rst = 0;
        load_weight = 1; w_in = 8'sd5;
        a_in = 8'sd0; sum_in = 32'sd0; en = 0;
        @(negedge clk);
        load_weight = 0;
        check_ao(0, "no-en holds a_out after weight load");

        // Test: en=1, feed a_in=3, sum_in=0. Expect next cycle:
        // a_out = 3 (pass-through), sum_out = 0 + 5*3 = 15
        en = 1; a_in = 8'sd3; sum_in = 32'sd0;
        @(negedge clk);
        check_ao(32'sd3, "pass-through a_in=3");
        check_so(32'sd15, "sum = 0 + 5*3");

        // Test: feed a_in=-2, sum_in=100. Expect sum_out = 100 + 5*(-2) = 90
        a_in = -8'sd2; sum_in = 32'sd100;
        @(negedge clk);
        check_ao(-8'sd2, "pass-through a_in=-2");
        check_so(32'sd90, "sum = 100 + 5*(-2)");

        // Test: en=0 should hold both a_out and sum_out despite new inputs
        en = 0; a_in = 8'sd127; sum_in = 32'sd999;
        @(negedge clk);
        check_ao(-8'sd2, "en=0 holds a_out");
        check_so(32'sd90, "en=0 holds sum_out");

        // Test: reload weight mid-stream to -4, then compute
        en = 1; load_weight = 1; w_in = -8'sd4;
        a_in = 8'sd10; sum_in = 32'sd0;
        @(negedge clk);
        load_weight = 0;
        // weight updates same cycle as latched (non-blocking), so this
        // cycle's product still used the OLD weight (5) since load_weight
        // and the MAC update happen in the same always block/cycle using
        // the pre-update `weight` value read at clock edge.
        // a*w = 10*5 = 50 (weight becomes -4 for NEXT cycle)
        check_so(32'sd50, "product uses pre-update weight (5) this edge");

        // Next cycle: weight is now -4
        a_in = 8'sd2; sum_in = 32'sd0;
        @(negedge clk);
        check_so(-32'sd8, "sum uses newly loaded weight -4: 0 + (-4*2)");

        $display("----------------------------------------");
        if (errors == 0)
            $display("ALL %0d TESTS PASSED", test_num);
        else
            $display("%0d/%0d TESTS FAILED", errors, test_num);
        $display("----------------------------------------");

        $finish;
    end

endmodule
