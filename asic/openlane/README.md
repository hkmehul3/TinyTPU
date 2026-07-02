# Running OpenLane physical design on TinyTPU

**This flow was not run as part of building this RTL.** OpenLane requires its
own Docker-based toolchain and a process design kit (PDK, e.g. SkyWater
130nm), which isn't available in the sandboxed environment used to build and
simulate this project. Any synthesis reports, area numbers, or timing
closure results should come from actually running this flow, not be assumed
or fabricated.

## Prerequisites

- Docker installed and running
- ~15GB free disk space (PDK + tool images)
- macOS or Linux (Apple Silicon Macs: OpenLane's Docker images run under
  Rosetta emulation, which works but is slow -- budget extra time)

## Setup (one-time)

```bash
git clone https://github.com/The-OpenROAD-Project/OpenLane.git
cd OpenLane
make          # pulls the Docker image and the sky130 PDK; takes a while
```

## Running TinyTPU through the flow

```bash
# from the OpenLane repo root
cp -r /path/to/TinyTPU/asic/openlane ./designs/tinytpu
make mount
# inside the container:
./flow.tcl -design tinytpu
```

## What to expect

- `top.v`'s `en` and `rst` are treated as ordinary ports here; a full ASIC
  flow would also want you to add proper reset synchronization and a real
  clock gating strategy before tapeout-quality closure -- this config gets
  you a first-pass synthesizable result, not a signoff-ready one.
- Expect to iterate on `PL_TARGET_DENSITY` and `DIE_AREA` if the initial run
  doesn't converge cleanly on placement/routing -- this is completely normal
  for a first pass and not a sign anything is wrong with the RTL.
- After a successful run, `runs/<timestamp>/reports/` will have real area,
  power, and timing numbers you can cite -- use those actual numbers rather
  than estimating them.

## If you don't have time to run this before an application deadline

That's fine and worth saying plainly: a working, verified RTL design with a
real AXI4-Lite interface (which this project has) is already a strong
portfolio piece on its own. Physical implementation (Phase 5) is a
legitimately separate skill area from RTL design and verification (Phases
1-4) -- many strong hardware engineers specialize in one or the other. It's
better to accurately describe this project as "RTL design + verification,
FPGA/ASIC-flow-ready" than to claim synthesis results you haven't actually
generated.
