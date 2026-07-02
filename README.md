# TinyTPU: An INT8 AI Accelerator ASIC

A synthesizable systolic-array AI accelerator, built and verified module-by-module,
with a real AXI4-Lite control interface. Every module in this repo has been
independently unit-tested AND proven correct as part of a full chip-level
integration test driven purely through AXI4-Lite transactions.

## Status

| Module | RTL | Test | Result |
|---|---|---|---|
| MAC unit | `rtl/mac.v` | `tb/tb_mac.sv` | 8/8 passing |
| Processing Element | `rtl/pe.v` | `tb/tb_pe.sv` | 11/11 passing |
| 8x8 Systolic Array | `rtl/systolic_array.v` | `tb/tb_array.sv` | verified vs golden matmul |
| Input Buffer (skew) | `rtl/input_buffer.v` | `tb/tb_input_buffer.sv` | 89/89 passing |
| Output Buffer (de-skew) | `rtl/output_buffer.v` | `tb/tb_output_buffer.sv` | 9/9 passing |
| SRAM Controller | `rtl/sram_controller.v` | `tb/tb_sram_controller.sv` | 11/11 passing |
| DMA engine | `rtl/dma.v` | `tb/tb_dma.sv` | 80/80 passing |
| AXI4-Lite slave | `rtl/axi_lite_slave.v` | `tb/tb_axi_lite_slave.sv` | 4/4 passing |
| Controller FSM + top-level | `rtl/controller.v`, `rtl/top.v` | `tb/tb_top.sv` | full chip, all checks passing |

Integration tests (proving modules compose correctly together):
- `tb/tb_ib_array_integration.sv` — input_buffer -> systolic_array
- `tb/tb_full_pipeline.sv` — input_buffer -> systolic_array -> output_buffer
- `tb/tb_dma.sv` — sram_controller -> dma -> input_buffer
- `tb/tb_top.sv` — **the whole chip**, driven entirely through real AXI4-Lite
  write/read transactions (weights loaded via AXI, activation data loaded into
  source SRAM, START pulsed via AXI CTRL register, STATUS polled via AXI reads,
  results read back via AXI RESULT registers) -- and checked against an
  independently-computed golden matrix-vector product.

## Architecture

```
   AXI4-Lite
       |
  axi_lite_slave  (real AW/W/B and AR/R handshakes)
       |
   controller (FSM: LOAD_WEIGHTS -> DMA_ACT -> COMPUTE -> CAPTURE)
       |
   +---+-----------------------+
   |                           |
  dma  <---- src SRAM     input_buffer (diagonal skew)
   |                           |
   +----> input_buffer.mem     |
                                v
                        8x8 systolic_array (weight-stationary)
                                |
                                v
                        output_buffer (de-skew, align results)
                                |
                                v
                        result registers (read via AXI)
```

## Register Map (word-addressed, `controller.v`)

| Address | Name | Access | Description |
|---|---|---|---|
| 0x00 | CTRL | W | bit0 = START (self-clearing pulse) |
| 0x01 | STATUS | R | bit0 = DONE (sticky until next START) |
| 0x02 | NUM_COLS | R/W | activation column count for this run |
| 0x10-0x4F | WEIGHT[r][c] | W | 64 words, row-major, flat index r*8+c |
| 0x50-0x57 | RESULT[0..7] | R | one INT32 result per output column |

## Running the tests

Requires Icarus Verilog (`brew install icarus-verilog` on Mac, `apt install
iverilog` on Linux).

```bash
# Individual module tests
iverilog -g2012 -o tb_mac.out rtl/mac.v tb/tb_mac.sv && vvp tb_mac.out
iverilog -g2012 -o tb_pe.out rtl/pe.v tb/tb_pe.sv && vvp tb_pe.out
# ... see docs/ARCHITECTURE.md for the full list of build commands

# The big one: full chip test via real AXI transactions
iverilog -g2012 -o tb_top.out rtl/mac.v rtl/pe.v rtl/systolic_array.v \
  rtl/input_buffer.v rtl/output_buffer.v rtl/sram_controller.v rtl/dma.v \
  rtl/axi_lite_slave.v rtl/controller.v rtl/top.v tb/tb_top.sv
vvp tb_top.out
```

## Documented simplifications (honest, not hidden)

- **Broadcast weight load**: all 64 weights load in a single cycle via a wide
  bus. Real silicon typically shifts weights in serially to avoid the wide
  routing. A serial-load version is a natural "v2" extension.
- **DMA is not a full AXI4 burst master**: it demonstrates the core DMA
  control concept (address generation, transfer counting, completion
  signaling) against a simplified single-beat source memory interface,
  rather than implementing full AXI4 burst semantics (AWLEN, burst type,
  etc.).
- **Source SRAM is a side-port, not AXI-memory-mapped**: the activation
  source memory is loaded via a direct write port rather than through the
  AXI4-Lite interface itself, to keep the register map scope reasonable.
- **LATENCY_OFFSET=9 in output_buffer is a measured, not derived, constant**
  for this specific pipeline configuration (see docs/ARCHITECTURE.md for how
  it was found). If the upstream pipeline depth changes (e.g. inserting the
  SRAM controller's own latency into the activation path), this must be
  re-verified.

## Verification depth (see docs/VERIFICATION.md)

This project has directed, self-checking testbenches with golden-model
comparison for every module, plus a small set of SystemVerilog assertions on
the controller FSM. It does **not** include functional coverage collection or
constrained-random verification -- see docs/VERIFICATION.md for what a fuller
industrial verification pass would add.

## Physical Design (ASIC)

See `asic/openlane/` for a starter OpenLane configuration. **This was not run
in the environment that built this RTL** -- OpenLane requires its own Docker
toolchain and a PDK (SkyWater 130nm), which needs to be run separately (see
`asic/openlane/README.md` for instructions). Any synthesis, timing, or area
reports should come from an actual OpenLane run, not be assumed.
