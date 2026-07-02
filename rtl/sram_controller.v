// =============================================================
// Module: sram_controller
// A simple synchronous single-port SRAM model with standard
// 1-cycle registered read latency (matches real SRAM macro
// timing: address in on cycle N, data out on cycle N+1).
// Byte-write not implemented (word-granularity writes only) --
// documented simplification for this portfolio scope.
// =============================================================

module sram_controller #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8,
    parameter DEPTH      = 256
)(
    input  wire                    clk,
    input  wire                    rst,

    input  wire                    wr_en,
    input  wire [ADDR_WIDTH-1:0]   wr_addr,
    input  wire [DATA_WIDTH-1:0]   wr_data,

    input  wire                    rd_en,
    input  wire [ADDR_WIDTH-1:0]   rd_addr,
    output reg  [DATA_WIDTH-1:0]   rd_data,
    output reg                     rd_valid
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_data  <= {DATA_WIDTH{1'b0}};
            rd_valid <= 1'b0;
        end else begin
            if (wr_en)
                mem[wr_addr] <= wr_data;

            rd_valid <= rd_en;
            if (rd_en)
                rd_data <= mem[rd_addr];
        end
    end

endmodule
