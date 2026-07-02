`timescale 1ns/1ps
module tb_dma;
    localparam DATA_WIDTH = 8;
    localparam ROWS = 8;
    localparam MAX_COLS = 16;
    localparam COL_ADDR_W = 5;
    localparam SRC_ADDR_W = 9;
    localparam TEST_COLS = 3;

    reg clk, rst;
    // source SRAM write port (testbench loads it directly, simulating a
    // host having already placed data in "source memory")
    reg src_wr_en;
    reg [SRC_ADDR_W-1:0] src_wr_addr;
    reg signed [DATA_WIDTH-1:0] src_wr_data_s;
    wire [DATA_WIDTH-1:0] src_wr_data = src_wr_data_s;

    wire src_rd_en_w;
    wire [SRC_ADDR_W-1:0] src_rd_addr_w;
    wire [DATA_WIDTH-1:0] src_rd_data_w;
    wire src_rd_valid_w;

    reg dma_start;
    reg [COL_ADDR_W-1:0] num_cols;
    wire dma_busy, dma_done;
    wire dst_wr_en_w;
    wire [2:0] dst_wr_row_w;
    wire [COL_ADDR_W-1:0] dst_wr_col_w;
    wire signed [DATA_WIDTH-1:0] dst_wr_data_w;

    wire ib_busy, ib_done;
    reg ib_start;
    reg [COL_ADDR_W-1:0] ib_num_cols;
    wire signed [ROWS*DATA_WIDTH-1:0] a_out_flat;

    integer i, j;
    integer errors = 0, test_num = 0;
    reg signed [DATA_WIDTH-1:0] SRC [0:ROWS-1][0:TEST_COLS-1];

    sram_controller #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(SRC_ADDR_W), .DEPTH(ROWS*MAX_COLS)) src_mem (
        .clk(clk), .rst(rst),
        .wr_en(src_wr_en), .wr_addr(src_wr_addr), .wr_data(src_wr_data),
        .rd_en(src_rd_en_w), .rd_addr(src_rd_addr_w), .rd_data(src_rd_data_w), .rd_valid(src_rd_valid_w)
    );

    dma #(.DATA_WIDTH(DATA_WIDTH), .ROWS(ROWS), .MAX_COLS(MAX_COLS), .COL_ADDR_W(COL_ADDR_W), .SRC_ADDR_W(SRC_ADDR_W)) dut (
        .clk(clk), .rst(rst),
        .start(dma_start), .num_cols(num_cols), .busy(dma_busy), .done(dma_done),
        .src_rd_en(src_rd_en_w), .src_rd_addr(src_rd_addr_w),
        .src_rd_data($signed(src_rd_data_w)), .src_rd_valid(src_rd_valid_w),
        .dst_wr_en(dst_wr_en_w), .dst_wr_row(dst_wr_row_w), .dst_wr_col(dst_wr_col_w), .dst_wr_data(dst_wr_data_w)
    );

    input_buffer #(.DATA_WIDTH(DATA_WIDTH), .ROWS(ROWS), .MAX_COLS(MAX_COLS), .COL_ADDR_W(COL_ADDR_W)) ib (
        .clk(clk), .rst(rst),
        .wr_en(dst_wr_en_w), .wr_row(dst_wr_row_w), .wr_col(dst_wr_col_w), .wr_data(dst_wr_data_w),
        .start(ib_start), .num_cols(ib_num_cols),
        .busy(ib_busy), .done(ib_done),
        .a_out_flat(a_out_flat)
    );

    always #5 clk = ~clk;

    task check_row(input [2:0] row, input signed [DATA_WIDTH-1:0] expected, input [127:0] name);
        reg signed [DATA_WIDTH-1:0] actual;
        begin
            actual = a_out_flat[(row+1)*DATA_WIDTH-1 -: DATA_WIDTH];
            test_num = test_num + 1;
            if (actual !== expected) begin
                $display("[FAIL] Test %0d (%0s) row%0d: expected=%0d got=%0d", test_num, name, row, expected, actual);
                errors = errors + 1;
            end else
                $display("[PASS] Test %0d (%0s) row%0d: %0d", test_num, name, row, actual);
        end
    endtask

    initial begin
        clk=0; rst=1; src_wr_en=0; src_wr_addr=0; src_wr_data_s=0;
        dma_start=0; num_cols=0; ib_start=0; ib_num_cols=0;
        @(negedge clk); @(negedge clk); rst=0;

        // Fill source memory with known values: row*10+col
        for (i = 0; i < ROWS; i = i + 1)
            for (j = 0; j < TEST_COLS; j = j + 1)
                SRC[i][j] = i*10 + j;

        for (i = 0; i < ROWS; i = i + 1) begin
            for (j = 0; j < TEST_COLS; j = j + 1) begin
                src_wr_en = 1; src_wr_addr = i*MAX_COLS + j; src_wr_data_s = SRC[i][j];
                @(negedge clk);
            end
        end
        src_wr_en = 0;

        // Kick off DMA transfer into input_buffer
        num_cols = TEST_COLS;
        dma_start = 1;
        @(negedge clk);
        dma_start = 0;

        // Wait for DMA done
        i = 0;
        while (!dma_done && i < 200) begin @(negedge clk); i = i + 1; end
        if (!dma_done) begin
            $display("[FAIL] DMA never completed (timeout)");
            errors = errors + 1;
        end else begin
            $display("[INFO] DMA completed after %0d cycles", i);
        end
        @(negedge clk); // let done pulse settle

        // Now trigger input_buffer streaming and verify skewed output
        ib_num_cols = TEST_COLS;
        ib_start = 1;
        @(negedge clk);
        ib_start = 0;

        for (i = 0; i <= (ROWS-1)+TEST_COLS-1; i = i + 1) begin
            @(negedge clk);
            for (j = 0; j < ROWS; j = j + 1) begin
                integer diff;
                diff = i - j;
                if (diff >= 0 && diff < TEST_COLS)
                    check_row(j[2:0], SRC[j][diff], "dma-then-skew");
                else
                    check_row(j[2:0], 0, "dma-then-skew-zero");
            end
        end

        $display("----------------------------------------");
        if (errors == 0) $display("ALL %0d DMA-CHAIN TESTS PASSED", test_num);
        else $display("%0d/%0d FAILED", errors, test_num);
        $display("----------------------------------------");
        $finish;
    end
endmodule
