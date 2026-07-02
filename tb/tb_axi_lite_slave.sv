`timescale 1ns/1ps
module tb_axi_lite_slave;
    localparam AW = 8, DW = 32;
    reg clk, rst;
    reg [AW-1:0] awaddr, araddr;
    reg awvalid, wvalid, arvalid, bready, rready;
    reg [DW-1:0] wdata;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [DW-1:0] rdata;

    wire reg_wr_en;
    wire [AW-1:0] reg_wr_addr;
    wire [DW-1:0] reg_wr_data;
    wire reg_rd_en;
    wire [AW-1:0] reg_rd_addr;
    reg [DW-1:0] reg_rd_data;

    // simple backing register file to exercise the slave against
    reg [DW-1:0] regfile [0:255];

    integer errors = 0, test_num = 0;

    axi_lite_slave #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW)) dut (
        .clk(clk), .rst(rst),
        .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready),
        .reg_wr_en(reg_wr_en), .reg_wr_addr(reg_wr_addr), .reg_wr_data(reg_wr_data),
        .reg_rd_en(reg_rd_en), .reg_rd_addr(reg_rd_addr), .reg_rd_data(reg_rd_data)
    );

    always #5 clk = ~clk;

    // backend register file: write side reacts to reg_wr_en, read side is
    // combinational (mimics a fast register file)
    always @(posedge clk) begin
        if (reg_wr_en) regfile[reg_wr_addr] <= reg_wr_data;
    end
    always @(*) reg_rd_data = regfile[reg_rd_addr];

    task axi_write(input [AW-1:0] addr, input [DW-1:0] data);
        begin
            @(negedge clk);
            awaddr = addr; awvalid = 1; wdata = data; wvalid = 1; bready = 1;
            @(negedge clk);
            while (!awready) @(negedge clk);
            awvalid = 0; wvalid = 0;
            while (!bvalid) @(negedge clk);
            @(negedge clk); // let bvalid clear
        end
    endtask

    task axi_read(output [DW-1:0] data);
        begin
            @(negedge clk);
            araddr = 0; arvalid = 1; rready = 1;
            // set actual address
            araddr = araddr; // placeholder, real addr set by caller before call
            @(negedge clk);
            while (!arready) @(negedge clk);
            arvalid = 0;
            while (!rvalid) @(negedge clk);
            data = rdata;
            @(negedge clk);
        end
    endtask

    reg [DW-1:0] read_result;

    initial begin
        clk=0; rst=1; awaddr=0; araddr=0; awvalid=0; wvalid=0; arvalid=0;
        bready=0; rready=0; wdata=0;
        @(negedge clk); @(negedge clk); rst=0;

        // Test 1: write then read back a register
        axi_write(8'h10, 32'hDEADBEEF);
        test_num = test_num + 1;
        if (regfile[8'h10] !== 32'hDEADBEEF) begin
            $display("[FAIL] Test %0d: AXI write didn't land in regfile, got=%h", test_num, regfile[8'h10]);
            errors = errors + 1;
        end else
            $display("[PASS] Test %0d: AXI write landed correctly (0x%h)", test_num, regfile[8'h10]);

        // Test 2: read it back via the AXI read channel
        @(negedge clk);
        araddr = 8'h10; arvalid = 1; rready = 1;
        @(negedge clk);
        while (!arready) @(negedge clk);
        arvalid = 0;
        while (!rvalid) @(negedge clk);
        read_result = rdata;
        @(negedge clk);
        test_num = test_num + 1;
        if (read_result !== 32'hDEADBEEF) begin
            $display("[FAIL] Test %0d: AXI read got=%h expected=DEADBEEF", test_num, read_result);
            errors = errors + 1;
        end else
            $display("[PASS] Test %0d: AXI read returned 0x%h", test_num, read_result);

        // Test 3: write a different address, confirm isolation
        axi_write(8'h20, 32'h12345678);
        test_num = test_num + 1;
        if (regfile[8'h20] !== 32'h12345678 || regfile[8'h10] !== 32'hDEADBEEF) begin
            $display("[FAIL] Test %0d: register isolation broken", test_num);
            errors = errors + 1;
        end else
            $display("[PASS] Test %0d: register isolation correct", test_num);

        // Test 4: multiple sequential writes
        axi_write(8'h30, 32'h1);
        axi_write(8'h34, 32'h2);
        axi_write(8'h38, 32'h3);
        test_num = test_num + 1;
        if (regfile[8'h30] !== 1 || regfile[8'h34] !== 2 || regfile[8'h38] !== 3) begin
            $display("[FAIL] Test %0d: sequential writes failed", test_num);
            errors = errors + 1;
        end else
            $display("[PASS] Test %0d: sequential writes correct", test_num);

        $display("----------------------------------------");
        if (errors == 0) $display("ALL %0d AXI4-LITE TESTS PASSED", test_num);
        else $display("%0d/%0d FAILED", errors, test_num);
        $display("----------------------------------------");
        $finish;
    end
endmodule
