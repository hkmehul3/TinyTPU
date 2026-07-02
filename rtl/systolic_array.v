// =============================================================
// Module: systolic_array
// An ROWSxCOLS grid of weight-stationary PEs.
//
// Design choices (documented, not hidden):
//   - EXTERNAL SKEW: this module does NOT skew inputs internally.
//     The caller (testbench now, input_buffer module later) is
//     responsible for feeding each row's activation stream
//     staggered by `row_index` cycles. This keeps the array
//     itself simple and independently verifiable.
//   - BROADCAST WEIGHT LOAD: every PE has its own dedicated
//     w_in slice and shares a common load_weight strobe, so all
//     64 weights load in a single cycle. Not realistic for actual
//     silicon (real designs shift weights in serially to avoid a
//     64-wide bus), but correct and simplest to verify first.
//     A serial-load version can be layered on top later.
//
// Ports use flattened buses (row-major) since plain Verilog
// module ports can't carry unpacked multi-dim arrays cleanly:
//   w_in_flat[(r*COLS+c+1)*DW-1 -: DW]      = weight for PE(r,c)
//   a_in_flat[(r+1)*DW-1 -: DW]             = west input for row r
//   a_out_flat[(r+1)*DW-1 -: DW]            = east output of row r
//   sum_in_flat[(c+1)*AW-1 -: AW]           = north input for col c
//   sum_out_flat[(c+1)*AW-1 -: AW]          = south output of col c
// =============================================================

module systolic_array #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32,
    parameter ROWS       = 8,
    parameter COLS       = 8
)(
    input  wire                                    clk,
    input  wire                                    rst,
    input  wire                                    en,

    input  wire                                    load_weight,
    input  wire signed [ROWS*COLS*DATA_WIDTH-1:0]  w_in_flat,

    input  wire signed [ROWS*DATA_WIDTH-1:0]       a_in_flat,
    output wire signed [ROWS*DATA_WIDTH-1:0]       a_out_flat,

    input  wire signed [COLS*ACC_WIDTH-1:0]        sum_in_flat,
    output wire signed [COLS*ACC_WIDTH-1:0]        sum_out_flat
);

    // Internal link wires. a_link[r][c] is the activation wire
    // entering PE(r,c) from the west (c=0 comes from a_in_flat,
    // c=COLS is the row's east-edge output).
    wire signed [DATA_WIDTH-1:0] a_link [0:ROWS-1][0:COLS];

    // sum_link[r][c] is the partial-sum wire entering PE(r,c) from
    // the north (r=0 comes from sum_in_flat, r=ROWS is the column's
    // south-edge output).
    wire signed [ACC_WIDTH-1:0] sum_link [0:ROWS][0:COLS-1];

    genvar r, c;

    generate
        // Wire up row west-edge inputs / east-edge outputs
        for (r = 0; r < ROWS; r = r + 1) begin : ROW_EDGE
            assign a_link[r][0] = a_in_flat[(r+1)*DATA_WIDTH-1 -: DATA_WIDTH];
            assign a_out_flat[(r+1)*DATA_WIDTH-1 -: DATA_WIDTH] = a_link[r][COLS];
        end

        // Wire up column north-edge inputs / south-edge outputs
        for (c = 0; c < COLS; c = c + 1) begin : COL_EDGE
            assign sum_link[0][c] = sum_in_flat[(c+1)*ACC_WIDTH-1 -: ACC_WIDTH];
            assign sum_out_flat[(c+1)*ACC_WIDTH-1 -: ACC_WIDTH] = sum_link[ROWS][c];
        end

        // Instantiate the grid
        for (r = 0; r < ROWS; r = r + 1) begin : PE_ROW
            for (c = 0; c < COLS; c = c + 1) begin : PE_COL
                pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) pe_inst (
                    .clk         (clk),
                    .rst         (rst),
                    .en          (en),
                    .load_weight (load_weight),
                    .w_in        (w_in_flat[((r*COLS+c)+1)*DATA_WIDTH-1 -: DATA_WIDTH]),
                    .a_in        (a_link[r][c]),
                    .a_out       (a_link[r][c+1]),
                    .sum_in      (sum_link[r][c]),
                    .sum_out     (sum_link[r+1][c])
                );
            end
        end
    endgenerate

endmodule
