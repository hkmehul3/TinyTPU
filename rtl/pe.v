// =============================================================
// Module: pe (Processing Element)
// Dataflow: Weight-stationary systolic array building block.
//
//   - Weight `w` is loaded once (load_weight=1) and held fixed
//     for the duration of a matmul pass.
//   - Activation flows west->east: a_in this cycle appears on
//     a_out next cycle (registered pass-through), so it ripples
//     across a row with a 1-cycle-per-PE skew.
//   - Partial sum flows north->south: sum_in + (w * a_in) is
//     registered out to sum_out.
//   - `en` gates whether the datapath advances this cycle
//     (pipeline stall support).
// =============================================================

module pe #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                          clk,
    input  wire                          rst,         // async, active-high

    input  wire                          en,          // advance datapath
    input  wire                          load_weight, // latch w this cycle
    input  wire signed [DATA_WIDTH-1:0]  w_in,        // weight to load

    input  wire signed [DATA_WIDTH-1:0]  a_in,        // activation in (west)
    output reg  signed [DATA_WIDTH-1:0]  a_out,       // activation out (east)

    input  wire signed [ACC_WIDTH-1:0]   sum_in,      // partial sum in (north)
    output reg  signed [ACC_WIDTH-1:0]   sum_out      // partial sum out (south)
);

    reg signed [DATA_WIDTH-1:0] weight;

    wire signed [2*DATA_WIDTH-1:0] product;
    assign product = weight * a_in;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            weight  <= {DATA_WIDTH{1'b0}};
            a_out   <= {DATA_WIDTH{1'b0}};
            sum_out <= {ACC_WIDTH{1'b0}};
        end else begin
            if (load_weight)
                weight <= w_in;

            if (en) begin
                a_out   <= a_in;
                sum_out <= sum_in + {{(ACC_WIDTH-2*DATA_WIDTH){product[2*DATA_WIDTH-1]}}, product};
            end
        end
    end

endmodule
