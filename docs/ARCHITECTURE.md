# TinyTPU Architecture

## Dataflow: weight-stationary systolic matmul

TinyTPU computes `y = x^T W` for an 8x8 weight matrix `W` and activation
vector(s) `x`, using a classic weight-stationary systolic array:

- Each of the 64 Processing Elements (PEs) holds one weight, loaded once per
  run and held fixed for the whole computation.
- Activations enter from the west edge of the array, one row at a time, and
  ripple eastward one PE per cycle (a registered pass-through).
- Partial sums enter from the north edge (zero, for a fresh computation) and
  accumulate southward, picking up `weight * activation` at each PE they pass
  through.
- Because activations take 1 cycle per PE to cross a row, and partial sums
  take 1 cycle per PE to descend a column, a **diagonal input skew** is
  required: row `r`'s activation must enter `r` cycles after row 0's, so that
  by the time it reaches column `c`, it lines up with the correct partial sum
  from all `c+1` rows that have already contributed. Get this skew wrong and
  the simulation runs fine but produces silently wrong numbers -- this is why
  the array and its skewing logic (`input_buffer`) were verified with
  self-checking golden-model comparisons, not just "did it compile."

## Why external skew (array/buffer split)

The skew logic lives in `input_buffer.v`, not `systolic_array.v`. This keeps
the array itself a simple, independently-testable grid, and matches how a
real design separates "compute" from "data staging" concerns -- the input
buffer is exactly where a real design's data formatting/skewing logic
belongs, since it already needs to exist as a memory stage regardless.

## Latency measurement methodology

Rather than deriving pipeline latencies by hand (error-prone for a design
this size), each integration testbench in this project used one of two
approaches:

1. **Search-based verification** (`tb_array.sv`): capture output over a
   generous cycle window, and search for each expected golden value,
   independently confirming both correctness AND self-consistent latency
   (column `c+1`'s result should appear exactly 1 cycle after column `c`'s).
2. **Empirical sweep** (`output_buffer`'s `LATENCY_OFFSET`): when the first
   guess (8) was wrong, the actual pipeline was instrumented directly (raw
   `sum_out_flat` printed every cycle) to observe the true arrival cycle (9),
   then that value was verified via a parameter sweep before being locked in
   as a documented, empirically-verified constant.

This is a deliberate choice: guessing pipeline latency by hand and asserting
it's correct without simulation evidence is exactly the kind of mistake this
project was built to avoid.

## FSM: controller.v

```
IDLE --(START via AXI CTRL)--> LOAD_WEIGHTS --> DMA_ACT --(dma_done)-->
START_COMPUTE --> COMPUTE --(result_valid)--> CAPTURE --> IDLE
```

Key ordering constraint: `input_buffer` streaming must not begin until the
DMA has **finished** writing activation data into its memory -- otherwise the
input buffer would read stale/unwritten values. This was caught during
integration (an earlier draft pulsed `dma_start` and `ib_start` on the same
cycle) and fixed by adding an explicit `S_DMA_ACT` wait state gated on
`dma_done`.

## Build commands for every test in the project

```bash
iverilog -g2012 -o tb_mac.out rtl/mac.v tb/tb_mac.sv && vvp tb_mac.out
iverilog -g2012 -o tb_pe.out rtl/pe.v tb/tb_pe.sv && vvp tb_pe.out
iverilog -g2012 -o tb_array.out rtl/mac.v rtl/pe.v rtl/systolic_array.v tb/tb_array.sv && vvp tb_array.out
iverilog -g2012 -o tb_ib.out rtl/input_buffer.v tb/tb_input_buffer.sv && vvp tb_ib.out
iverilog -g2012 -o tb_integ.out rtl/mac.v rtl/pe.v rtl/systolic_array.v rtl/input_buffer.v tb/tb_ib_array_integration.sv && vvp tb_integ.out
iverilog -g2012 -o tb_ob.out rtl/output_buffer.v tb/tb_output_buffer.sv && vvp tb_ob.out
iverilog -g2012 -o tb_full.out rtl/mac.v rtl/pe.v rtl/systolic_array.v rtl/input_buffer.v rtl/output_buffer.v tb/tb_full_pipeline.sv && vvp tb_full.out
iverilog -g2012 -o tb_sram.out rtl/sram_controller.v tb/tb_sram_controller.sv && vvp tb_sram.out
iverilog -g2012 -o tb_dma.out rtl/sram_controller.v rtl/dma.v rtl/input_buffer.v tb/tb_dma.sv && vvp tb_dma.out
iverilog -g2012 -o tb_axi.out rtl/axi_lite_slave.v tb/tb_axi_lite_slave.sv && vvp tb_axi.out
iverilog -g2012 -o tb_top.out rtl/mac.v rtl/pe.v rtl/systolic_array.v rtl/input_buffer.v rtl/output_buffer.v rtl/sram_controller.v rtl/dma.v rtl/axi_lite_slave.v rtl/controller.v rtl/top.v tb/tb_top.sv && vvp tb_top.out
```
