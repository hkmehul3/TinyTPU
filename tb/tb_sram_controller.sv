`timescale 1ns/1ps
module tb_sram_controller;
    localparam DW = 32, AW = 8, DEPTH = 256;
    reg clk, rst, wr_en, rd_en;
    reg [AW-1:0] wr_addr, rd_addr;
    reg [DW-1:0] wr_data;
    wire [DW-1:0] rd_data;
    wire rd_valid;
    integer errors = 0, test_num = 0, i;

    sram_controller #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW), .DEPTH(DEPTH)) dut (
        .clk(clk), .rst(rst), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data), .rd_valid(rd_valid));

    always #5 clk = ~clk;

    task check(input [DW-1:0] expected, input [127:0] name);
        begin
            test_num = test_num + 1;
            if (rd_data !== expected || !rd_valid) begin
                $display("[FAIL] Test %0d (%0s): expected=%0d got=%0d valid=%0d", test_num, name, expected, rd_data, rd_valid);
                errors = errors + 1;
            end else
                $display("[PASS] Test %0d (%0s): %0d", test_num, name, rd_data);
        end
    endtask

    initial begin
        clk=0; rst=1; wr_en=0; rd_en=0; wr_addr=0; rd_addr=0; wr_data=0;
        @(negedge clk); @(negedge clk); rst=0;

        // Write 10 known values
        for (i = 0; i < 10; i = i + 1) begin
            wr_en = 1; wr_addr = i; wr_data = i * 100 + 7;
            @(negedge clk);
        end
        wr_en = 0;

        // Read them back, 1-cycle latency
        for (i = 0; i < 10; i = i + 1) begin
            rd_en = 1; rd_addr = i;
            @(negedge clk);
            rd_en = 0;
            check(i*100+7, "readback");
        end

        // rd_valid should deassert when rd_en is low
        rd_en = 0;
        @(negedge clk);
        test_num = test_num + 1;
        if (rd_valid !== 1'b0) begin
            $display("[FAIL] Test %0d: rd_valid should be 0 when rd_en=0", test_num);
            errors = errors + 1;
        end else
            $display("[PASS] Test %0d: rd_valid=0 when idle", test_num);

        $display("----------------------------------------");
        if (errors == 0) $display("ALL %0d TESTS PASSED", test_num);
        else $display("%0d/%0d FAILED", errors, test_num);
        $display("----------------------------------------");
        $finish;
    end
endmodule
