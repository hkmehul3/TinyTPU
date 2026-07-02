`timescale 1ns/1ps
module tb_top;
    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = 32;
    localparam ROWS = 8, COLS = 8, MAX_COLS = 16;
    localparam COL_ADDR_W = 5, SRC_ADDR_W = 9;
    localparam AW = 8, DW = 32;

    reg clk, rst;
    reg [AW-1:0] awaddr, araddr;
    reg awvalid, wvalid, arvalid, bready, rready;
    reg [DW-1:0] wdata;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [DW-1:0] rdata;
    reg src_wr_en;
    reg [SRC_ADDR_W-1:0] src_wr_addr;
    reg signed [DATA_WIDTH-1:0] src_wr_data;

    integer i, j;
    integer errors = 0;
    reg signed [DATA_WIDTH-1:0] W [0:ROWS-1][0:COLS-1];
    reg signed [DATA_WIDTH-1:0] X [0:ROWS-1];
    reg signed [ACC_WIDTH-1:0]  golden [0:COLS-1];

    top #(
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .ROWS(ROWS), .COLS(COLS),
        .MAX_COLS(MAX_COLS), .COL_ADDR_W(COL_ADDR_W), .SRC_ADDR_W(SRC_ADDR_W),
        .AXI_ADDR_W(AW), .AXI_DATA_W(DW)
    ) dut (
        .clk(clk), .rst(rst),
        .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready),
        .src_wr_en(src_wr_en), .src_wr_addr(src_wr_addr), .src_wr_data(src_wr_data)
    );

    always #5 clk = ~clk;

    task axi_write(input [AW-1:0] addr, input [DW-1:0] data);
        begin
            @(negedge clk);
            awaddr = addr; awvalid = 1; wdata = data; wvalid = 1; bready = 1;
            @(negedge clk);
            while (!awready) @(negedge clk);
            awvalid = 0; wvalid = 0;
            while (!bvalid) @(negedge clk);
            @(negedge clk);
        end
    endtask

    reg [DW-1:0] axi_rd_result;
    task axi_read(input [AW-1:0] addr);
        begin
            @(negedge clk);
            araddr = addr; arvalid = 1; rready = 1;
            @(negedge clk);
            while (!arready) @(negedge clk);
            arvalid = 0;
            while (!rvalid) @(negedge clk);
            axi_rd_result = rdata;
            @(negedge clk);
        end
    endtask

    initial begin
        clk=0; rst=1; awaddr=0; araddr=0; awvalid=0; wvalid=0; arvalid=0;
        bready=0; rready=0; wdata=0; src_wr_en=0; src_wr_addr=0; src_wr_data=0;
        @(negedge clk); @(negedge clk); rst=0;

        // Same W, X used throughout this whole project for apples-to-apples
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

        // 1. Write weights via AXI (word addrs 0x10..0x4F, row-major r*COLS+c)
        for (i = 0; i < ROWS; i = i + 1)
            for (j = 0; j < COLS; j = j + 1)
                axi_write(8'h10 + (i*COLS+j), {{(DW-DATA_WIDTH){W[i][j][DATA_WIDTH-1]}}, W[i][j]});

        // 2. Write activation vector X into source SRAM directly (side port)
        for (i = 0; i < ROWS; i = i + 1) begin
            src_wr_en = 1; src_wr_addr = i * MAX_COLS + 0; src_wr_data = X[i];
            @(negedge clk);
        end
        src_wr_en = 0;

        // 3. Set NUM_COLS = 1 via AXI
        axi_write(8'h02, 32'd1);

        // 4. Pulse START via AXI (CTRL bit0)
        axi_write(8'h00, 32'd1);

        // 5. Poll STATUS until DONE, via AXI reads
        i = 0;
        axi_rd_result = 0;
        while (axi_rd_result[0] !== 1'b1 && i < 300) begin
            axi_read(8'h01);
            i = i + 1;
        end

        if (axi_rd_result[0] !== 1'b1) begin
            $display("[FAIL] STATUS never showed DONE after %0d polls (timeout)", i);
            errors = errors + 1;
        end else begin
            $display("[INFO] DONE observed after %0d AXI status polls", i);

            // 6. Read back RESULT registers via AXI and compare to golden
            for (j = 0; j < COLS; j = j + 1) begin
                axi_read(8'h50 + j);
                if ($signed(axi_rd_result) !== golden[j]) begin
                    $display("[FAIL] RESULT[%0d]: expected=%0d got=%0d", j, golden[j], $signed(axi_rd_result));
                    errors = errors + 1;
                end else begin
                    $display("[PASS] RESULT[%0d] = %0d (via AXI read)", j, $signed(axi_rd_result));
                end
            end
        end

        $display("----------------------------------------");
        if (errors == 0)
            $display("FULL CHIP TEST: ALL CHECKS PASSED (driven entirely via AXI4-Lite)");
        else
            $display("FULL CHIP TEST: %0d CHECK(S) FAILED", errors);
        $display("----------------------------------------");
        $finish;
    end
endmodule
