# digital-systems-vhdl

A small FPGA-oriented system written in VHDL-2008: a 16-bit multi-cycle CPU
(control FSM + synchronous datapath), a synchronous SRAM interface with
configurable wait states, a memory-mapped UART with baud generator and FIFOs,
and generic counters. Every block has a self-checking GHDL testbench, and the
complete SoC runs assembled programs whose final state is checked against a
Python instruction-set simulator, cycle for cycle.

Everything reported below comes from RTL simulation with GHDL. Vivado
project/constraint files for a Basys3 board are included but were **not run**
(no Vivado or board was available), so no utilisation, timing or hardware
results are claimed.

## Features

- **CPU** (`rtl/cpu.vhd`, `control_unit.vhd`, `datapath.vhd`)
  - 16-bit words, 8 registers (r0 = 0), 12 opcodes: R-type ALU (add, sub,
    and, or, xor, slt, sll, srl), addi, lui/lli, lw/sw, beq/bne, jal, jr,
    nop, halt.
  - Classic multi-cycle organisation: PC, IR, MDR, A/B latches and ALUOut
    around one ALU; a 15-state Moore/Mealy FSM drives a record-typed
    control word.
  - Request/ready memory bus, so memory latency is a parameter of the
    memory system, not of the CPU.
  - 32-bit cycle and retired-instruction counters built from the generic
    `counter` block.
- **Memory interface** (`sram_ctrl.vhd`, `sync_sram.vhd`): bridges the CPU bus onto a
  synchronous SRAM with `WAIT_STATES` extra cycles; the RAM model infers a
  dual-port block RAM and loads its contents from a hex file.
- **UART** (`baud_gen.vhd`, `uart_tx.vhd`, `uart_rx.vhd`, `uart_ctrl.vhd`): 8N1, 16x
  oversampling, two-flop RX synchroniser, mid-bit start validation,
  framing-error detection, 8-deep TX/RX FIFOs and a status register.
- **SoC** (`soc_top.vhd`): address decode for RAM (0x0000-0x0FFF), UART,
  LEDs, switches and a cycle-counter register; `fpga_top.vhd` adds reset
  synchronisation and board pin mapping.
- **Toolchain** (`tools/`): two-pass assembler with labels, expressions,
  pseudo-instructions (`li`, `call`, `ret`, `beqz`...) and directives; an
  ISS with a cycle model that mirrors the FSM and memory wait states.

## Layout

```
rtl/        VHDL design (package, ALU, register file, datapath, control FSM,
            CPU, counter, FIFO, SRAM + controller, UART, SoC, board top)
tb/         self-checking testbenches + tb_pkg (checker, LCG)
programs/   assembly programs run on the CPU in simulation
tools/      asm.py (assembler), iss.py (instruction-set simulator / compare)
scripts/    run_tests.py (full regression), sweep_wait_states.py,
            docker_run.sh (runs any command inside the HDL tool container)
tests/      pytest suite for the assembler and ISS
fpga/       basys3.xdc, create_project.tcl, build.tcl, program_board.tcl
results/    generated tables (CSV + Markdown)
```

## Instruction set

| Format | Bits | Instructions |
|---|---|---|
| R | `0000 rd rs1 rs2 funct` | add sub and or xor slt sll srl |
| I | `op rd rs1 simm6` | addi, lw, sw, beq, bne (PC-relative) |
| U | `op rd 0 imm8` | lui (rd = imm8 << 8), lli (rd[7:0] = imm8) |
| J | `1000 rd simm9` | jal (rd = PC + 1, PC-relative) |
| - | `1001 000 rs1 000000` | jr |
| - | `1110 ...` / `1111 ...` | nop / halt |

Cycle cost (W = SRAM wait states): fetch 2 + W, decode 1, ALU/immediate
ops +2, load +2 + (2 + W), store +1 + (2 + W), branch/jump +1. I/O
accesses complete in one cycle.

## How to run

GHDL and Python 3 are needed. `scripts/docker_run.sh` runs any command in a
container image that has them (`HDL_IMAGE` selects the image):

```bash
# full regression: 7 unit testbench runs + 10 program runs, writes results/
scripts/docker_run.sh python3 scripts/run_tests.py
# same with GHW waveforms for GTKWave in build/
scripts/docker_run.sh python3 scripts/run_tests.py --waves
# wait-state sweep (20 SoC simulations)
scripts/docker_run.sh python3 scripts/sweep_wait_states.py
# assembler / ISS unit tests (host Python with pytest)
python -m pytest -q tests

# assemble and run a program on the ISS only
python3 tools/asm.py programs/sieve.asm -o build/sieve.hex -l build/sieve.lst
python3 tools/iss.py build/sieve.hex
```

With GHDL installed locally, `make test`, `make waves` and `make pytest` do the same.

## Verification approach

- Unit testbenches compare each block against an independent model written
  in the testbench (integer-arithmetic ALU reference, queue model for the
  FIFO, shadow memory for the SRAM controller, cycle-by-cycle counter model).
- `tb_uart` runs TX to RX loopback for all 256 byte values, checks the TX line
  with a separate behavioural receiver (start/stop bits, frame length), drives
  the RX pin with +/-1.5 % and +/-3 % baud error, and injects a framing error.
- `tb_soc` loads a program into the SRAM, drives UART input, decodes UART
  output, waits for HALT and dumps registers, 1024 RAM words and counters.
  `tools/iss.py compare` then checks every register, every dumped RAM word,
  the UART byte stream and (for programs without I/O polling) the exact
  instruction and cycle counts.

## Results

Produced by `scripts/docker_run.sh python3 scripts/run_tests.py` (GHDL 4.1.0,
mcode backend). Full tables: `results/testbench_results.md`.

| Run | Checks | Failures | Simulated clock cycles |
|---|---:|---:|---:|
| tb_alu (810 directed + 3000 random vectors) | 13254 | 0 | combinational |
| tb_regfile | 1033 | 0 | 1013 |
| tb_counter | 16001 | 0 | 4003 |
| tb_fifo | 19068 | 0 | 5003 |
| tb_uart | 1877 | 0 | 100138 |
| tb_sram_ctrl (0 wait states) | 10809 | 0 | 7534 |
| tb_sram_ctrl (3 wait states) | 19809 | 0 | 16534 |
| 10 SoC program runs (TB + ISS checks) | 10465 | 0 | 78890 |
| **Total** | **92316** | **0** | **213115** |

Most SoC checks are word-by-word RAM comparisons against the ISS (1024 per
run), so they say more about end-state equality than about separate features.

Programs on the CPU (RTL cycles from the hardware cycle counter):

| Program | What it does | Wait states | Instructions | RTL cycles | ISS cycles | CPI |
|---|---|---:|---:|---:|---:|---:|
| isa_test | every opcode + ALU edge cases | 0 | 60 | 310 | 310 | 5.17 |
| fib | 24 Fibonacci numbers to RAM | 0 | 174 | 868 | 868 | 4.99 |
| sort | bubble sort, 16 signed words | 0 | 1028 | 5487 | 5487 | 5.34 |
| muldiv | shift-add multiply + GCD subroutines | 0 | 1579 | 7101 | 7101 | 4.50 |
| sieve | primes below 128 (finds 31) | 0 | 2356 | 11459 | 11459 | 4.86 |
| hello | prints `Hello from the VHDL CPU!\r\n` | 0 | 856 | 4279 | n/a | 4.999 |
| echo | upper-cases UART input `Hello, vhdl world.` | 0 | 692 | 3445 | n/a | 4.98 |

For `hello` and `echo` the CPU spends most of its time polling the UART status
register, so their instruction counts depend on UART timing; only their
architectural state and UART output are compared with the ISS.

SRAM wait-state sweep (`scripts/sweep_wait_states.py`, all 20 runs match the
ISS cycle model exactly):

| Program | 0 WS cycles | 1 WS | 2 WS | 3 WS | 4 WS | Slowdown at 4 WS |
|---|---:|---:|---:|---:|---:|---:|
| fib | 868 | 1066 | 1264 | 1462 | 1660 | 1.91x |
| sort | 5487 | 6879 | 8271 | 9663 | 11055 | 2.02x |
| muldiv | 7101 | 8728 | 10355 | 11982 | 13609 | 1.92x |
| sieve | 11459 | 14164 | 16869 | 19574 | 22279 | 1.94x |

Each instruction fetches from RAM, so each wait state adds at least one cycle
to every instruction. `sort` slows down most because it has the highest
share of loads and stores.

## FPGA build files (not run)

`fpga/basys3.xdc` maps the 100 MHz clock, centre button (reset), 16 switches,
16 LEDs and the USB-UART pins of a Basys3 (XC7A35T). `fpga/create_project.tcl`
creates a project, and `fpga/build.tcl` runs non-project-mode synthesis,
implementation, reports and bitstream generation, with the program image
passed as the `INIT_FILE` generic. These scripts have not been run here
because Vivado is not installed, so there are no timing-closure or
utilisation figures. `BAUD_DIVISOR = 54` gives 115 740 baud from 100 MHz
(0.47 % above 115 200).

## Limitations

- Simulation only; the design has not been synthesised or run on a board.
- No interrupts, no pipeline, no caches; `jr`/`jal` are the only indirect
  control flow. Branch offsets are limited to -32..+31 words.
- The UART has no parity or flow control.
- The ISS models the UART as always ready, so its cycle counts are only
  exact for programs that do not poll I/O.
