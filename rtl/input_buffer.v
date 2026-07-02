// =============================================================
// Module: input_buffer
// Purpose: Holds an ROWS x MAX_COLS activation matrix and streams
//          it out to the systolic array with the diagonal skew
//          the array itself does NOT do (see systolic_array.v
//          header: external skew is a deliberate design choice).
//
// Behavior:
//   - Host writes data[row][col] via wr_en/wr_row/wr_col/wr_data
//     while idle.
//   - Host asserts `start` for one cycle with `num_cols` set to
//     how many columns of real data are loaded.
//   - From then on, each cycle t (t=0,1,2,...) the buffer drives
//     a_in_flat such that row r carries data[r][t-r] whenever
//     0 <= t-r < num_cols, and 0 otherwise. This is exactly the
//     diagonal skew: row r's first real value appears at cycle r.
//   - `done` pulses high for one cycle once the last valid value
//     has been driven (t-r == num_cols-1 for row ROWS-1).
//   - `busy` is high from `start` until `done`.
// =============================================================

module input_buffer #(
    parameter DATA_WIDTH = 8,
    parameter ROWS       = 8,
    parameter MAX_COLS   = 16,
    parameter COL_ADDR_W = 5   // must cover MAX_COLS-1
)(
    input  wire                          clk,
    input  wire                          rst,

    // write port (use while idle)
    input  wire                          wr_en,
    input  wire [2:0]                    wr_row,   // 0..ROWS-1 (ROWS<=8 assumed)
    input  wire [COL_ADDR_W-1:0]         wr_col,
    input  wire signed [DATA_WIDTH-1:0]  wr_data,

    // control
    input  wire                          start,
    input  wire [COL_ADDR_W-1:0]         num_cols, // number of valid columns (>=1)

    output reg                           busy,
    output reg                           done,

    // streaming output to systolic_array's a_in_flat
    output reg signed [ROWS*DATA_WIDTH-1:0] a_out_flat
);

    reg signed [DATA_WIDTH-1:0] mem [0:ROWS-1][0:MAX_COLS-1];

    reg [COL_ADDR_W-1:0] t;          // cycle counter since start
    reg [COL_ADDR_W-1:0] num_cols_r; // latched column count

    integer r;
    // t - r as signed to detect "not yet started for this row"
    integer diff;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy       <= 1'b0;
            done       <= 1'b0;
            t          <= {COL_ADDR_W{1'b0}};
            num_cols_r <= {COL_ADDR_W{1'b0}};
            a_out_flat <= {(ROWS*DATA_WIDTH){1'b0}};
        end else begin
            done <= 1'b0; // default; pulses only when we hit the last cycle

            if (wr_en && !busy) begin
                mem[wr_row][wr_col] <= wr_data;
            end

            if (start && !busy) begin
                busy       <= 1'b1;
                t          <= {COL_ADDR_W{1'b0}};
                num_cols_r <= num_cols;
            end else if (busy) begin
                // drive outputs for current t, then advance
                for (r = 0; r < ROWS; r = r + 1) begin
                    diff = t - r;
                    if (diff >= 0 && diff < num_cols_r)
                        a_out_flat[(r+1)*DATA_WIDTH-1 -: DATA_WIDTH] <= mem[r][diff];
                    else
                        a_out_flat[(r+1)*DATA_WIDTH-1 -: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
                end

                // last useful cycle is when row ROWS-1 gets its last value:
                // t - (ROWS-1) == num_cols_r - 1  =>  t == ROWS-1+num_cols_r-1
                if (t == (ROWS - 1) + num_cols_r - 1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end

                t <= t + 1'b1;
            end
        end
    end

endmodule
