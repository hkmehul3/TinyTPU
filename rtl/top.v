// =============================================================
// Module: top (TinyTPU)
// Top-level chip integration: AXI4-Lite slave -> controller FSM
// -> {DMA, input_buffer, systolic_array, output_buffer}, with a
// source SRAM holding activation data the host DMA's from.
//
// A host writes weights + control regs via AXI, writes raw
// activation data directly into src SRAM via a simple side port
// (documented simplification -- a full implementation would also
// memory-map the source SRAM through AXI; kept as a direct port
// here since AXI write-to-SRAM is architecturally identical to the
// register writes already verified in axi_lite_slave and doesn't
// add new design risk).
// =============================================================

module top #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32,
    parameter ROWS       = 8,
    parameter COLS       = 8,
    parameter MAX_COLS   = 16,
    parameter COL_ADDR_W = 5,
    parameter SRC_ADDR_W = 9,
    parameter AXI_ADDR_W = 8,
    parameter AXI_DATA_W = 32
)(
    input  wire clk,
    input  wire rst,

    // AXI4-Lite control/data interface
    input  wire [AXI_ADDR_W-1:0] awaddr,
    input  wire                  awvalid,
    output wire                  awready,
    input  wire [AXI_DATA_W-1:0] wdata,
    input  wire                  wvalid,
    output wire                  wready,
    output wire [1:0]            bresp,
    output wire                  bvalid,
    input  wire                  bready,
    input  wire [AXI_ADDR_W-1:0] araddr,
    input  wire                  arvalid,
    output wire                  arready,
    output wire [AXI_DATA_W-1:0] rdata,
    output wire [1:0]            rresp,
    output wire                  rvalid,
    input  wire                  rready,

    // source activation memory side-port (host loads raw data here)
    input  wire                        src_wr_en,
    input  wire [SRC_ADDR_W-1:0]       src_wr_addr,
    input  wire signed [DATA_WIDTH-1:0] src_wr_data
);

    wire reg_wr_en;
    wire [AXI_ADDR_W-1:0] reg_wr_addr;
    wire [AXI_DATA_W-1:0] reg_wr_data;
    wire reg_rd_en;
    wire [AXI_ADDR_W-1:0] reg_rd_addr;
    wire [AXI_DATA_W-1:0] reg_rd_data;

    axi_lite_slave #(.ADDR_WIDTH(AXI_ADDR_W), .DATA_WIDTH(AXI_DATA_W)) axi (
        .clk(clk), .rst(rst),
        .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready),
        .reg_wr_en(reg_wr_en), .reg_wr_addr(reg_wr_addr), .reg_wr_data(reg_wr_data),
        .reg_rd_en(reg_rd_en), .reg_rd_addr(reg_rd_addr), .reg_rd_data(reg_rd_data)
    );

    wire src_rd_en;
    wire [SRC_ADDR_W-1:0] src_rd_addr;
    wire [DATA_WIDTH-1:0] src_rd_data_u;
    wire src_rd_valid;

    sram_controller #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(SRC_ADDR_W), .DEPTH(ROWS*MAX_COLS)) src_mem (
        .clk(clk), .rst(rst),
        .wr_en(src_wr_en), .wr_addr(src_wr_addr), .wr_data(src_wr_data),
        .rd_en(src_rd_en), .rd_addr(src_rd_addr), .rd_data(src_rd_data_u), .rd_valid(src_rd_valid)
    );

    controller #(
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .ROWS(ROWS), .COLS(COLS),
        .MAX_COLS(MAX_COLS), .COL_ADDR_W(COL_ADDR_W), .SRC_ADDR_W(SRC_ADDR_W), .REG_ADDR_W(AXI_ADDR_W)
    ) ctrl (
        .clk(clk), .rst(rst),
        .reg_wr_en(reg_wr_en), .reg_wr_addr(reg_wr_addr), .reg_wr_data(reg_wr_data),
        .reg_rd_en(reg_rd_en), .reg_rd_addr(reg_rd_addr), .reg_rd_data(reg_rd_data),
        .src_rd_en(src_rd_en), .src_rd_addr(src_rd_addr),
        .src_rd_data($signed(src_rd_data_u)), .src_rd_valid(src_rd_valid)
    );

endmodule
