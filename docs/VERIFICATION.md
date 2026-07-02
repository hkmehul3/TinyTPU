# Verification: what's here, and what a fuller pass would add

## What this project actually has

- **Directed, self-checking testbenches** for every module, each comparing
  against an independently-computed expected value (not just "it ran without
  crashing").
- **Golden-model comparison** for the matmul-producing modules (systolic
  array, full pipeline, full chip) -- expected results are computed via a
  separate reference calculation in the testbench, not hand-derived and
  potentially wrong.
- **Integration tests** proving modules compose correctly, not just pass in
  isolation (input_buffer+array, full pipeline, DMA chain, full chip via AXI).
- **A small set of SystemVerilog structural assertions** on the controller
  FSM (illegal state detection, `done_sticky` only transitions from the
  correct state, `load_weight` never asserted while idle).
- **Debugged, evidence-based fixes**: every timing assumption that turned out
  wrong (output_buffer's `LATENCY_OFFSET`, the DMA/input_buffer race
  condition) was caught by actually running simulations and instrumenting
  the design, not by manual re-derivation.

## What this project does NOT have (honestly)

This is directed verification, not the kind of coverage-driven verification
a real ASIC team would require before tapeout:

- **No functional coverage collection** -- there's no coverage model tracking
  which corner cases (all-zero weights, max-magnitude INT8 values, back-to-back
  runs without reset, num_cols=0 or num_cols=MAX_COLS boundary, etc.) have
  actually been exercised.
- **No constrained-random verification** -- all test vectors are hand-picked
  directed values, not randomized within realistic constraints across many
  seeds.
- **No formal verification** -- no property checking beyond the handful of
  simulation-time assertions above.
- **Limited edge-case testing** -- e.g. what happens if START is pulsed while
  the FSM is mid-run (not IDLE)? The current `S_IDLE: if (start_pulse)` gate
  means a START during a run is currently silently ignored, which is
  reasonable but not explicitly tested.
- **No timing/gate-level simulation** -- everything here is RTL/behavioral
  simulation only; no back-annotated timing verification post-synthesis.

## What a fuller verification pass would add

1. A functional coverage model (SystemVerilog covergroups) tracking weight
   value ranges, activation value ranges, num_cols values exercised, and FSM
   state transition coverage.
2. Constrained-random test generation across many seeds, with the existing
   golden-model checkers reused as the scoreboard.
3. Formal assertions on the AXI4-Lite protocol itself (e.g. AWVALID must stay
   asserted until AWREADY, using an off-the-shelf AXI protocol checker).
4. Explicit directed tests for FSM edge cases (START during a run, back-to-
   back runs, reset mid-run).
5. Gate-level simulation with back-annotated SDF timing after synthesis.

This document exists so that anyone reviewing this project (including an
interviewer) sees an accurate picture of verification maturity rather than an
inflated one.
