// =============================================================
// Module: controller
// Top-level sequencing FSM, sitting behind axi_lite_slave's
// register interface. Register map (word address, byte addr = word*4):
//   word 0x00 CTRL:      bit0 = START (pulse to begin a run)
//   word 0x01 STATUS:    bit0 = DONE (sticky until next START)
//   word 0x02 NUM_COLS:  activation column count (1..MAX_COLS)
//   word 0x10-0x4F: WEIGHT[r][c], flat index r*COLS+c (64 words)
//   word 0x50-0x57: RESULT[0..7]
//
// FSM: IDLE -> (START) -> LOAD_WEIGHTS -> DMA_ACT -> COMPUTE ->
//      CAPTURE -> DONE -> IDLE
//
// DOCUMENTED SIMPLIFICATION: activation source data for the DMA
// is assumed pre-loaded into src SRAM by the host before START
// (host writes it via a separate SRAM-mapped AXI region in a full
// implementation; wired directly to a source SRAM port here to
// keep register-map scope reasonable for this project stage).
// =============================================================

module controller #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32,
    parameter ROWS       = 8,
    parameter COLS       = 8,
    parameter MAX_COLS   = 16,
    parameter COL_ADDR_W = 5,
    parameter SRC_ADDR_W = 9,
    parameter REG_ADDR_W = 8
)(
    input  wire clk,
    input  wire rst,

    // register backend (from axi_lite_slave)
    input  wire                          reg_wr_en,
    input  wire [REG_ADDR_W-1:0]         reg_wr_addr,
    input  wire [31:0]                   reg_wr_data,
    input  wire                          reg_rd_en,
    input  wire [REG_ADDR_W-1:0]         reg_rd_addr,
    output reg  [31:0]                   reg_rd_data,

    // DMA source memory port (pass-through to an external sram_controller)
    output wire                          src_rd_en,
    output wire [SRC_ADDR_W-1:0]         src_rd_addr,
    input  wire signed [DATA_WIDTH-1:0]  src_rd_data,
    input  wire                          src_rd_valid
);

    // ---- Register file for CTRL/STATUS/NUM_COLS/WEIGHTS ----
    reg start_pulse;
    reg done_sticky;
    reg [COL_ADDR_W-1:0] num_cols_reg;
    reg signed [DATA_WIDTH-1:0] weight_regs [0:ROWS*COLS-1];
    reg signed [ACC_WIDTH-1:0]  result_regs [0:COLS-1];

    localparam ADDR_CTRL     = 8'h00;
    localparam ADDR_STATUS   = 8'h01;
    localparam ADDR_NUMCOLS  = 8'h02;
    localparam ADDR_WEIGHT_BASE = 8'h10; // words 0x10..0x4F (64 words)
    localparam ADDR_RESULT_BASE = 8'h50; // words 0x50..0x57

    integer wi;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            start_pulse  <= 1'b0;
            num_cols_reg <= 0;
            for (wi = 0; wi < ROWS*COLS; wi = wi + 1) weight_regs[wi] <= 0;
        end else begin
            start_pulse <= 1'b0;
            if (reg_wr_en) begin
                if (reg_wr_addr == ADDR_CTRL && reg_wr_data[0])
                    start_pulse <= 1'b1;
                else if (reg_wr_addr == ADDR_NUMCOLS)
                    num_cols_reg <= reg_wr_data[COL_ADDR_W-1:0];
                else if (reg_wr_addr >= ADDR_WEIGHT_BASE && reg_wr_addr < ADDR_WEIGHT_BASE + ROWS*COLS)
                    weight_regs[reg_wr_addr - ADDR_WEIGHT_BASE] <= reg_wr_data[DATA_WIDTH-1:0];
            end
        end
    end

    // combinational register read mux
    always @(*) begin
        if (reg_rd_addr == ADDR_STATUS)
            reg_rd_data = {31'b0, done_sticky};
        else if (reg_rd_addr == ADDR_NUMCOLS)
            reg_rd_data = {{(32-COL_ADDR_W){1'b0}}, num_cols_reg};
        else if (reg_rd_addr >= ADDR_RESULT_BASE && reg_rd_addr < ADDR_RESULT_BASE + COLS)
            reg_rd_data = result_regs[reg_rd_addr - ADDR_RESULT_BASE];
        else
            reg_rd_data = 32'h0;
    end

    // ---- Datapath submodule wiring ----
    wire signed [ROWS*DATA_WIDTH-1:0] a_link_flat;
    reg  dma_start;
    wire dma_busy, dma_done;
    wire dst_wr_en_w;
    wire [2:0] dst_wr_row_w;
    wire [COL_ADDR_W-1:0] dst_wr_col_w;
    wire signed [DATA_WIDTH-1:0] dst_wr_data_w;

    dma #(.DATA_WIDTH(DATA_WIDTH), .ROWS(ROWS), .MAX_COLS(MAX_COLS), .COL_ADDR_W(COL_ADDR_W), .SRC_ADDR_W(SRC_ADDR_W)) dma_inst (
        .clk(clk), .rst(rst),
        .start(dma_start), .num_cols(num_cols_reg), .busy(dma_busy), .done(dma_done),
        .src_rd_en(src_rd_en), .src_rd_addr(src_rd_addr),
        .src_rd_data(src_rd_data), .src_rd_valid(src_rd_valid),
        .dst_wr_en(dst_wr_en_w), .dst_wr_row(dst_wr_row_w), .dst_wr_col(dst_wr_col_w), .dst_wr_data(dst_wr_data_w)
    );

    reg ib_start;
    wire ib_busy, ib_done;
    input_buffer #(.DATA_WIDTH(DATA_WIDTH), .ROWS(ROWS), .MAX_COLS(MAX_COLS), .COL_ADDR_W(COL_ADDR_W)) ib_inst (
        .clk(clk), .rst(rst),
        .wr_en(dst_wr_en_w), .wr_row(dst_wr_row_w), .wr_col(dst_wr_col_w), .wr_data(dst_wr_data_w),
        .start(ib_start), .num_cols(num_cols_reg),
        .busy(ib_busy), .done(ib_done),
        .a_out_flat(a_link_flat)
    );

    reg en_array, load_weight;
    reg signed [ROWS*COLS*DATA_WIDTH-1:0] w_in_flat;
    wire signed [ROWS*DATA_WIDTH-1:0] a_out_flat_unused;
    reg signed [COLS*ACC_WIDTH-1:0] sum_in_flat_zero;
    wire signed [COLS*ACC_WIDTH-1:0] sum_out_flat;

    systolic_array #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .ROWS(ROWS), .COLS(COLS)) arr_inst (
        .clk(clk), .rst(rst), .en(en_array),
        .load_weight(load_weight), .w_in_flat(w_in_flat),
        .a_in_flat(a_link_flat), .a_out_flat(a_out_flat_unused),
        .sum_in_flat(sum_in_flat_zero), .sum_out_flat(sum_out_flat)
    );

    reg capture_start;
    wire ob_busy, result_valid;
    wire signed [COLS*ACC_WIDTH-1:0] result_flat;
    output_buffer #(.ACC_WIDTH(ACC_WIDTH), .COLS(COLS), .LATENCY_OFFSET(9)) ob_inst (
        .clk(clk), .rst(rst),
        .capture_start(capture_start),
        .sum_in_flat(sum_out_flat),
        .busy(ob_busy),
        .result_valid(result_valid),
        .result_flat(result_flat)
    );

    always @(*) begin
        sum_in_flat_zero = {(COLS*ACC_WIDTH){1'b0}};
        for (wi = 0; wi < ROWS*COLS; wi = wi + 1)
            w_in_flat[(wi+1)*DATA_WIDTH-1 -: DATA_WIDTH] = weight_regs[wi];
    end

    // ---- Main sequencing FSM ----
    localparam S_IDLE         = 0;
    localparam S_LOAD_WEIGHTS = 1;
    localparam S_DMA_ACT      = 2;
    localparam S_START_COMPUTE = 3;
    localparam S_COMPUTE      = 4;
    localparam S_CAPTURE      = 5;

    reg [2:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            done_sticky <= 1'b0;
            en_array <= 1'b0; load_weight <= 1'b0;
            dma_start <= 1'b0; ib_start <= 1'b0; capture_start <= 1'b0;
            for (wi = 0; wi < COLS; wi = wi + 1) result_regs[wi] <= 0;
        end else begin
            load_weight   <= 1'b0;
            dma_start     <= 1'b0;
            ib_start      <= 1'b0;
            capture_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        done_sticky <= 1'b0;
                        en_array    <= 1'b1;
                        load_weight <= 1'b1; // broadcast-load weights this cycle
                        state <= S_LOAD_WEIGHTS;
                    end
                end

                S_LOAD_WEIGHTS: begin
                    // weights latch into the PEs on the edge ending this cycle;
                    // now kick off the DMA transfer of activation data into
                    // the input_buffer's memory.
                    dma_start <= 1'b1;
                    state <= S_DMA_ACT;
                end

                S_DMA_ACT: begin
                    // wait for the DMA to fully populate input_buffer's memory
                    // BEFORE letting input_buffer start streaming/skewing it --
                    // starting streaming concurrently with the DMA write would
                    // read stale/unwritten data. This ordering matches exactly
                    // how tb_full_pipeline.sv verified LATENCY_OFFSET=9 (data
                    // fully loaded first, then start pulsed).
                    if (dma_done)
                        state <= S_START_COMPUTE;
                end

                S_START_COMPUTE: begin
                    ib_start      <= 1'b1;
                    capture_start <= 1'b1;
                    state <= S_COMPUTE;
                end

                S_COMPUTE: begin
                    if (result_valid)
                        state <= S_CAPTURE;
                end

                S_CAPTURE: begin
                    for (wi = 0; wi < COLS; wi = wi + 1)
                        result_regs[wi] <= result_flat[(wi+1)*ACC_WIDTH-1 -: ACC_WIDTH];
                    done_sticky <= 1'b1;
                    en_array <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ---- Basic SystemVerilog assertions (sanity properties) ----
    // These check structural invariants of the FSM; they are NOT a
    // substitute for a full functional coverage / randomized
    // verification plan (see docs/VERIFICATION.md for what a fuller
    // pass would add).
    `ifndef SYNTHESIS
        // FSM must never land in an undefined state encoding
        always @(posedge clk) if (!rst) begin
            assert (state == S_IDLE || state == S_LOAD_WEIGHTS || state == S_DMA_ACT ||
                    state == S_START_COMPUTE || state == S_COMPUTE || state == S_CAPTURE)
                else $error("ASSERTION FAILED: controller FSM in illegal state %0d", state);
        end

        // Track previous state/done_sticky manually (Icarus doesn't support $past)
        reg [2:0] state_prev;
        reg       done_sticky_prev;
        always @(posedge clk or posedge rst) begin
            if (rst) begin
                state_prev <= S_IDLE;
                done_sticky_prev <= 1'b0;
            end else begin
                state_prev <= state;
                done_sticky_prev <= done_sticky;
            end
        end

        // done_sticky must only ever transition 0->1 from within S_CAPTURE
        always @(posedge clk) if (!rst && done_sticky && !done_sticky_prev) begin
            assert (state_prev == S_CAPTURE)
                else $error("ASSERTION FAILED: done_sticky asserted outside S_CAPTURE");
        end

        // load_weight should never be asserted while the FSM is idle
        always @(posedge clk) if (!rst && state == S_IDLE) begin
            assert (!load_weight)
                else $error("ASSERTION FAILED: load_weight asserted while FSM idle");
        end
    `endif

endmodule
