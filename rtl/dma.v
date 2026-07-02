// =============================================================
// Module: dma
// Simplified DMA engine: transfers ROWS*num_cols elements from an
// external source memory (modeled as a simple synchronous
// read-address/read-data interface, standing in for a full AXI
// master burst read) into the input_buffer's write port.
//
// DOCUMENTED SIMPLIFICATION: this is not a full AXI4 burst master
// (no AWLEN/burst-type/response handling). It demonstrates the
// core DMA control concept -- address generation, transfer
// counting, destination sequencing, completion signaling -- which
// is the architecturally interesting part for a portfolio project.
// A production version would wrap this address-generation FSM
// with a real AXI4 master burst interface.
//
// Source layout assumed: row-major, src_addr = row*MAX_COLS + col.
// =============================================================

module dma #(
    parameter DATA_WIDTH = 8,
    parameter ROWS       = 8,
    parameter MAX_COLS   = 16,
    parameter COL_ADDR_W = 5,
    parameter SRC_ADDR_W = 9   // must cover ROWS*MAX_COLS
)(
    input  wire                          clk,
    input  wire                          rst,

    // control
    input  wire                          start,
    input  wire [COL_ADDR_W-1:0]         num_cols,
    output reg                           busy,
    output reg                           done,

    // source memory read interface (1-cycle latency, like sram_controller)
    output reg                           src_rd_en,
    output reg  [SRC_ADDR_W-1:0]         src_rd_addr,
    input  wire signed [DATA_WIDTH-1:0]  src_rd_data,
    input  wire                          src_rd_valid,

    // destination: input_buffer write port
    output reg                           dst_wr_en,
    output reg  [2:0]                    dst_wr_row,
    output reg  [COL_ADDR_W-1:0]         dst_wr_col,
    output reg signed [DATA_WIDTH-1:0]   dst_wr_data
);

    // simple sequencing: row-major counters, one element requested per cycle
    reg [2:0] row;
    reg [COL_ADDR_W-1:0] col;
    reg [COL_ADDR_W-1:0] num_cols_r;
    reg reading; // true while we've issued a read and are waiting for its data

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy <= 1'b0; done <= 1'b0;
            src_rd_en <= 1'b0; src_rd_addr <= 0;
            dst_wr_en <= 1'b0; dst_wr_row <= 0; dst_wr_col <= 0; dst_wr_data <= 0;
            row <= 0; col <= 0; num_cols_r <= 0; reading <= 1'b0;
        end else begin
            done      <= 1'b0;
            dst_wr_en <= 1'b0;
            src_rd_en <= 1'b0;

            if (start && !busy) begin
                busy <= 1'b1;
                row <= 0; col <= 0;
                num_cols_r <= num_cols;
                // issue first read immediately
                src_rd_en   <= 1'b1;
                src_rd_addr <= 0;
                reading <= 1'b1;
            end else if (busy) begin
                if (src_rd_valid) begin
                    // write the data we requested last cycle into the buffer
                    dst_wr_en   <= 1'b1;
                    dst_wr_row  <= row;
                    dst_wr_col  <= col;
                    dst_wr_data <= src_rd_data;

                    // advance row-major counters
                    if (col == num_cols_r - 1) begin
                        if (row == ROWS - 1) begin
                            // last element -- finish after this write
                            busy <= 1'b0;
                            done <= 1'b1;
                        end else begin
                            row <= row + 1'b1;
                            col <= 0;
                            src_rd_en   <= 1'b1;
                            src_rd_addr <= (row + 1) * MAX_COLS;
                        end
                    end else begin
                        col <= col + 1'b1;
                        src_rd_en   <= 1'b1;
                        src_rd_addr <= row * MAX_COLS + (col + 1);
                    end
                end
            end
        end
    end

endmodule
