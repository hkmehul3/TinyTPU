// =============================================================
// Module: mac
// Description: Signed INT8 x INT8 multiply, INT32 accumulate.
//              This is the base compute primitive for the
//              systolic array processing elements.
//
//   acc <= (clear) ? (a*b) : acc + (a*b)     -- on enable
//
// Notes:
//   - `clear` synchronously reloads the accumulator with just the
//     current product (used to start a new output computation
//     without a full module reset).
//   - `rst` is an async reset that zeroes everything.
//   - `en` gates whether accumulation happens this cycle (lets the
//     systolic array stall/hold state cleanly).
// =============================================================

module mac #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                        clk,
    input  wire                        rst,      // async, active-high
    input  wire                        en,       // accumulate enable
    input  wire                        clear,    // sync clear-and-load
    input  wire signed [DATA_WIDTH-1:0] a,
    input  wire signed [DATA_WIDTH-1:0] b,
    output reg  signed [ACC_WIDTH-1:0]  acc
);

    wire signed [2*DATA_WIDTH-1:0] product;
    assign product = a * b;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            acc <= {ACC_WIDTH{1'b0}};
        end else if (en) begin
            if (clear)
                acc <= {{(ACC_WIDTH-2*DATA_WIDTH){product[2*DATA_WIDTH-1]}}, product};
            else
                acc <= acc + {{(ACC_WIDTH-2*DATA_WIDTH){product[2*DATA_WIDTH-1]}}, product};
        end
        // en == 0: hold current value (no else needed, acc is a reg)
    end

endmodule
