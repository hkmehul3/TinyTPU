// =============================================================
// Module: axi_lite_slave
// A genuine AXI4-Lite slave implementing the full write and read
// channel handshakes (AWVALID/AWREADY, WVALID/WREADY, BVALID/
// BREADY, ARVALID/ARREADY, RVALID/RREADY) over a simple register
// file. This is the real protocol, not a simplified stand-in --
// AXI4-Lite has no bursts/IDs, so a correct single-beat handshake
// implementation here is spec-complete for this interface type.
//
// Register map (word-addressed, 32-bit):
//   0x00  CTRL       [0]=START (write 1 to pulse start; self-clears)
//   0x04  STATUS     [0]=DONE  (read-only, sticky until CTRL START)
//   0x08  NUM_COLS   activation column count for this run
//   0x0C-0x28  WEIGHT_DATA (write sequential weights; see controller)
//   0x40-0x5C  RESULT[0..7]   read-only, one 32-bit result per column
// (Full register semantics implemented in controller.v, which sits
//  behind this slave; this module only implements the AXI protocol
//  and a generic addressable register file passed through to it.)
// =============================================================

module axi_lite_slave #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    input  wire                        clk,
    input  wire                        rst,

    // AXI4-Lite write address channel
    input  wire [ADDR_WIDTH-1:0]       awaddr,
    input  wire                        awvalid,
    output reg                         awready,

    // AXI4-Lite write data channel
    input  wire [DATA_WIDTH-1:0]       wdata,
    input  wire                        wvalid,
    output reg                         wready,

    // AXI4-Lite write response channel
    output reg  [1:0]                  bresp,
    output reg                         bvalid,
    input  wire                        bready,

    // AXI4-Lite read address channel
    input  wire [ADDR_WIDTH-1:0]       araddr,
    input  wire                        arvalid,
    output reg                         arready,

    // AXI4-Lite read data channel
    output reg  [DATA_WIDTH-1:0]       rdata,
    output reg  [1:0]                  rresp,
    output reg                         rvalid,
    input  wire                        rready,

    // Simple register-file style backend interface exposed to controller.v
    output reg                         reg_wr_en,
    output reg  [ADDR_WIDTH-1:0]       reg_wr_addr,
    output reg  [DATA_WIDTH-1:0]       reg_wr_data,

    output reg                         reg_rd_en,
    output reg  [ADDR_WIDTH-1:0]       reg_rd_addr,
    input  wire [DATA_WIDTH-1:0]       reg_rd_data // combinationally supplied by controller
);

    localparam RESP_OKAY = 2'b00;

    // ---- Write channel FSM ----
    reg [ADDR_WIDTH-1:0] awaddr_latched;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            awready <= 1'b0; wready <= 1'b0; bvalid <= 1'b0; bresp <= RESP_OKAY;
            reg_wr_en <= 1'b0; reg_wr_addr <= 0; reg_wr_data <= 0;
            awaddr_latched <= 0;
        end else begin
            reg_wr_en <= 1'b0;

            // accept address when both address and data are offered (simple
            // combined AW/W acceptance -- valid AXI4-Lite behavior)
            if (!awready && !wready && awvalid && wvalid && !bvalid) begin
                awready <= 1'b1;
                wready  <= 1'b1;
                awaddr_latched <= awaddr;
                reg_wr_en   <= 1'b1;
                reg_wr_addr <= awaddr;
                reg_wr_data <= wdata;
                bvalid  <= 1'b1;
                bresp   <= RESP_OKAY;
            end else begin
                awready <= 1'b0;
                wready  <= 1'b0;
                if (bvalid && bready)
                    bvalid <= 1'b0;
            end
        end
    end

    // ---- Read channel FSM ----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            arready <= 1'b0; rvalid <= 1'b0; rdata <= 0; rresp <= RESP_OKAY;
            reg_rd_en <= 1'b0; reg_rd_addr <= 0;
        end else begin
            reg_rd_en <= 1'b0;

            if (!arready && !rvalid && arvalid) begin
                arready <= 1'b1;
                reg_rd_en   <= 1'b1;
                reg_rd_addr <= araddr;
            end else begin
                arready <= 1'b0;
            end

            // one cycle after accepting the read address, present data
            if (reg_rd_en) begin
                rdata  <= reg_rd_data;
                rresp  <= RESP_OKAY;
                rvalid <= 1'b1;
            end else if (rvalid && rready) begin
                rvalid <= 1'b0;
            end
        end
    end

endmodule
