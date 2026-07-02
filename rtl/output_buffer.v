// =============================================================
// Module: output_buffer
// Purpose: Captures the systolic array's staggered south-edge
//          outputs (sum_out_flat) into a single aligned result
//          vector, since column c's valid result appears
//          LATENCY_OFFSET + c cycles after `capture_start`.
//
// `capture_start` should be pulsed at the SAME reference cycle as
// the input_buffer's `start` pulse feeding the array upstream —
// LATENCY_OFFSET is the fixed, known pipeline depth from that
// point to column 0's result appearing (a designed constant, not
// runtime-detected, matching how real hardware pipeline latency
// is specified).
//
// `result_valid` pulses for one cycle once all COLS results have
// been latched; `result_flat` holds the full vector from then
// until the next capture_start.
// =============================================================

module output_buffer #(
    parameter ACC_WIDTH      = 32,
    parameter COLS           = 8,
    parameter LATENCY_OFFSET = 9,   // cycles from capture_start to column 0's result
                                     // (empirically verified for the input_buffer ->
                                     // systolic_array pipeline; re-verify if upstream
                                     // pipeline depth changes, e.g. adding SRAM controller)
    parameter CNT_WIDTH      = 6    // must cover LATENCY_OFFSET + COLS
)(
    input  wire                              clk,
    input  wire                              rst,

    input  wire                              capture_start,
    input  wire signed [COLS*ACC_WIDTH-1:0]  sum_in_flat,

    output reg                               busy,
    output reg                               result_valid,
    output reg signed [COLS*ACC_WIDTH-1:0]   result_flat
);

    reg [CNT_WIDTH-1:0] t;
    integer c;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy         <= 1'b0;
            result_valid <= 1'b0;
            t            <= {CNT_WIDTH{1'b0}};
            result_flat  <= {(COLS*ACC_WIDTH){1'b0}};
        end else begin
            result_valid <= 1'b0; // default; pulses only on the final capture cycle

            if (capture_start && !busy) begin
                busy <= 1'b1;
                t    <= {CNT_WIDTH{1'b0}};
            end else if (busy) begin
                for (c = 0; c < COLS; c = c + 1) begin
                    if (t == LATENCY_OFFSET + c)
                        result_flat[(c+1)*ACC_WIDTH-1 -: ACC_WIDTH] <= sum_in_flat[(c+1)*ACC_WIDTH-1 -: ACC_WIDTH];
                end

                if (t == LATENCY_OFFSET + COLS - 1) begin
                    busy         <= 1'b0;
                    result_valid <= 1'b1;
                end

                t <= t + 1'b1;
            end
        end
    end

endmodule
