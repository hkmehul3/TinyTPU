// =============================================================
// Testbench: tb_mac
// Verifies:
//   1. Reset zeroes accumulator
//   2. clear+en loads acc with fresh product (not added to old acc)
//   3. Repeated en (no clear) accumulates correctly across cycles
//   4. en=0 holds the accumulator value
//   5. Signed multiplication is correct (negative operands)
// =============================================================

`timescale 1ns/1ps

module tb_mac;

    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = 32;

    reg                         clk;
    reg                         rst;
    reg                         en;
    reg                         clear;
    reg  signed [DATA_WIDTH-1:0] a;
    reg  signed [DATA_WIDTH-1:0] b;
    wire signed [ACC_WIDTH-1:0]  acc;

    integer errors = 0;
    integer test_num = 0;

    mac #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) dut (
        .clk(clk), .rst(rst), .en(en), .clear(clear),
        .a(a), .b(b), .acc(acc)
    );

    // 100MHz clock
    always #5 clk = ~clk;

    task check(input signed [ACC_WIDTH-1:0] expected, input [127:0] name);
        begin
            test_num = test_num + 1;
            if (acc !== expected) begin
                $display("[FAIL] Test %0d (%0s): expected=%0d got=%0d",
                          test_num, name, expected, acc);
                errors = errors + 1;
            end else begin
                $display("[PASS] Test %0d (%0s): acc=%0d", test_num, name, acc);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_mac.vcd");
        $dumpvars(0, tb_mac);

        clk = 0; rst = 1; en = 0; clear = 0; a = 0; b = 0;
        @(negedge clk);
        @(negedge clk);

        // Test 1: reset holds acc at 0
        check(0, "reset");

        // Test 2: release reset, clear+en loads product (3*4=12)
        rst = 0; a = 8'sd3; b = 8'sd4; en = 1; clear = 1;
        @(negedge clk);
        clear = 0;
        check(32'sd12, "clear-load 3*4");

        // Test 3: accumulate again without clear (12 + 3*4 = 24)
        @(negedge clk);
        check(32'sd24, "accumulate +12");

        // Test 4: accumulate negative operand (-5 * 6 = -30) -> 24 - 30 = -6
        a = -8'sd5; b = 8'sd6;
        @(negedge clk);
        check(32'sd24 - 32'sd30, "accumulate negative");

        // Test 5: en=0 holds value even with changing inputs
        en = 0; a = 8'sd127; b = 8'sd127;
        @(negedge clk);
        check(32'sd24 - 32'sd30, "hold on en=0");

        // Test 6: clear reloads fresh product, discarding old acc
        en = 1; clear = 1; a = -8'sd1; b = -8'sd1; // (-1)*(-1)=1
        @(negedge clk);
        clear = 0;
        check(32'sd1, "clear reload after hold");

        // Test 7: max magnitude operands don't overflow ACC_WIDTH=32
        // -128 * 127 = -16256, well within int32 range
        clear = 1; a = -8'sd128; b = 8'sd127;
        @(negedge clk);
        clear = 0;
        check(-32'sd16256, "max magnitude product");

        // Test 8: async reset mid-operation
        @(negedge clk);
        rst = 1;
        @(negedge clk);
        check(0, "async reset mid-op");

        $display("----------------------------------------");
        if (errors == 0)
            $display("ALL %0d TESTS PASSED", test_num);
        else
            $display("%0d/%0d TESTS FAILED", errors, test_num);
        $display("----------------------------------------");

        $finish;
    end

endmodule
