#!/usr/bin/env python3
"""Instruction-set simulator and cycle model for the 16-bit multi-cycle CPU.

The ISS is the golden reference for the RTL: after a GHDL run, the testbench
dumps registers, a memory window, UART output and the cycle/instruction
counters, and `compare` checks them against this model.

The cycle model mirrors control_unit.vhd + sram_ctrl.vhd:
    FETCH (RAM)   2 + W cycles      (W = SRAM wait states)
    DECODE        1
    ALU/ADDI/LUI/LLI  EXEC 1 + WB 1
    LW            ADDR 1 + MEM (2 + W, or 1 for I/O) + WB 1
    SW            ADDR 1 + MEM (2 + W, or 1 for I/O)
    BEQ/BNE/JAL/JR    1
    NOP           0
    HALT          0 (counter stops when the HALT state is entered)

Usage:
    python3 tools/iss.py build/fib.hex [--wait-states N] [--uart-in TEXT]
    python3 tools/iss.py compare build/fib.hex build/fib.dump [...]
"""
from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field

MASK = 0xFFFF
MEM_WORDS = 4096
UART_DATA, UART_STATUS, LED, SWITCHES, CYCLES = 0xFF00, 0xFF01, 0xFF02, 0xFF03, 0xFF04


def sext(v: int, bits: int) -> int:
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def to_s16(v: int) -> int:
    return sext(v, 16)


@dataclass
class State:
    regs: list[int] = field(default_factory=lambda: [0] * 8)
    mem: list[int] = field(default_factory=lambda: [0] * MEM_WORDS)
    pc: int = 0
    cycles: int = 0
    instret: int = 0
    halted: bool = False
    illegal: bool = False
    uart_out: list[int] = field(default_factory=list)
    uart_in: list[int] = field(default_factory=list)
    leds: int = 0
    switches: int = 0


class ISS:
    def __init__(self, image: list[int], wait_states: int = 0,
                 uart_in: bytes = b"", switches: int = 0) -> None:
        self.s = State()
        for i, w in enumerate(image[:MEM_WORDS]):
            self.s.mem[i] = w & MASK
        self.ws = wait_states
        self.s.uart_in = list(uart_in)
        self.s.switches = switches & MASK

    # -- memory system -----------------------------------------------------
    def is_ram(self, addr: int) -> bool:
        return (addr >> 12) == 0

    def access_cycles(self, addr: int) -> int:
        return 2 + self.ws if self.is_ram(addr) else 1

    def load(self, addr: int) -> int:
        s = self.s
        if self.is_ram(addr):
            return s.mem[addr & 0xFFF]
        if addr == UART_DATA:
            return s.uart_in.pop(0) if s.uart_in else 0
        if addr == UART_STATUS:
            rx_avail = 1 if s.uart_in else 0
            # TX FIFO never fills and the transmitter is always idle in the
            # ISS; timing-dependent polling is therefore not cycle-exact.
            return (0 << 0) | (1 << 1) | (rx_avail << 2) | (1 << 4)
        if addr == LED:
            return s.leds
        if addr == SWITCHES:
            return s.switches
        if addr == CYCLES:
            return s.cycles & MASK
        return 0

    def store(self, addr: int, value: int) -> None:
        s = self.s
        if self.is_ram(addr):
            s.mem[addr & 0xFFF] = value & MASK
        elif addr == UART_DATA:
            s.uart_out.append(value & 0xFF)
        elif addr == LED:
            s.leds = value & MASK

    # -- execution -----------------------------------------------------------
    def step(self) -> None:
        s = self.s
        if s.halted:
            return
        ir = self.load(s.pc)
        cyc = self.access_cycles(s.pc) + 1  # fetch + decode
        s.pc = (s.pc + 1) & MASK
        op = ir >> 12
        rd = (ir >> 9) & 7
        rs1 = (ir >> 6) & 7
        rs2 = (ir >> 3) & 7
        r = s.regs

        def wr(idx: int, val: int) -> None:
            if idx:
                r[idx] = val & MASK

        if op == 0x0:
            a, b, f = r[rs1], r[rs2], ir & 7
            sh = b & 0xF
            res = [a + b, a - b, a & b, a | b, a ^ b,
                   1 if to_s16(a) < to_s16(b) else 0,
                   a << sh, a >> sh][f]
            wr(rd, res)
            cyc += 2
        elif op == 0x1:
            wr(rd, r[rs1] + sext(ir, 6))
            cyc += 2
        elif op == 0x2:
            wr(rd, (ir & 0xFF) << 8)
            cyc += 2
        elif op == 0x3:
            wr(rd, (r[rd] & 0xFF00) | (ir & 0xFF))
            cyc += 2
        elif op == 0x4:
            addr = (r[rs1] + sext(ir, 6)) & MASK
            wr(rd, self.load(addr))
            cyc += 1 + self.access_cycles(addr) + 1
        elif op == 0x5:
            addr = (r[rs1] + sext(ir, 6)) & MASK
            self.store(addr, r[rd])
            cyc += 1 + self.access_cycles(addr)
        elif op in (0x6, 0x7):
            equal = r[rd] == r[rs1]
            if equal == (op == 0x6):
                s.pc = (s.pc + sext(ir, 6)) & MASK
            cyc += 1
        elif op == 0x8:
            target = (s.pc + sext(ir, 9)) & MASK
            wr(rd, s.pc)
            s.pc = target
            cyc += 1
        elif op == 0x9:
            s.pc = r[rs1]
            cyc += 1
        elif op == 0xE:
            pass
        elif op == 0xF:
            s.halted = True
        else:
            s.illegal = True
        s.cycles += cyc
        s.instret += 1

    def run(self, max_instr: int = 1_000_000) -> State:
        for _ in range(max_instr):
            if self.s.halted:
                break
            self.step()
        return self.s


def load_hex(path: str) -> list[int]:
    with open(path, encoding="utf-8") as f:
        return [int(line, 16) for line in f if line.strip()]


def parse_dump(path: str) -> dict:
    """Parse the text dump written by tb_soc.vhd."""
    d: dict = {"regs": {}, "mem": {}, "uart": []}
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            key = parts[0]
            if key == "R":
                d["regs"][int(parts[1])] = int(parts[2], 16)
            elif key == "M":
                d["mem"][int(parts[1], 16)] = int(parts[2], 16)
            elif key == "U":
                d["uart"].append(int(parts[1], 16))
            elif key in ("CYCLES", "INSTRET", "HALTED", "ILLEGAL", "PC"):
                d[key.lower()] = int(parts[1], 16) if key == "PC" else int(parts[1])
    return d


def compare(hex_path: str, dump_path: str, wait_states: int, uart_in: bytes,
            check_cycles: bool) -> tuple[list[str], dict, State]:
    st = ISS(load_hex(hex_path), wait_states, uart_in).run()
    d = parse_dump(dump_path)
    errors: list[str] = []
    checks = 0
    for i in range(8):
        checks += 1
        if d["regs"].get(i) != st.regs[i]:
            errors.append(f"r{i}: rtl={d['regs'].get(i)} iss={st.regs[i]}")
    for addr, val in d["mem"].items():
        checks += 1
        if st.mem[addr] != val:
            errors.append(f"mem[0x{addr:03x}]: rtl=0x{val:04x} iss=0x{st.mem[addr]:04x}")
    checks += 1
    if d["uart"] != st.uart_out:
        errors.append(f"uart: rtl={bytes(d['uart'])!r} iss={bytes(st.uart_out)!r}")
    checks += 1
    if d.get("halted") != 1:
        errors.append("rtl did not halt")
    # Programs that poll UART status execute a timing-dependent number of
    # loop iterations, so instruction and cycle counts are only compared
    # for programs without I/O polling.
    if check_cycles:
        checks += 2
        if d.get("instret") != st.instret:
            errors.append(f"instret: rtl={d.get('instret')} iss={st.instret}")
        if d.get("cycles") != st.cycles:
            errors.append(f"cycles: rtl={d.get('cycles')} iss={st.cycles}")
    d["checks"] = checks
    return errors, d, st


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if argv and argv[0] == "compare":
        ap = argparse.ArgumentParser(prog="iss.py compare")
        ap.add_argument("hex")
        ap.add_argument("dump")
        ap.add_argument("--wait-states", type=int, default=0)
        ap.add_argument("--uart-in", default="")
        ap.add_argument("--no-cycles", action="store_true",
                        help="skip cycle comparison (programs that poll I/O)")
        a = ap.parse_args(argv[1:])
        errors, d, st = compare(a.hex, a.dump, a.wait_states,
                                a.uart_in.encode(), not a.no_cycles)
        status = "PASS" if not errors else "FAIL"
        print(f"ISS_COMPARE {status} checks={d['checks']} errors={len(errors)} "
              f"rtl_cycles={d.get('cycles')} iss_cycles={st.cycles} "
              f"instret={d.get('instret')}")
        for e in errors:
            print("  " + e)
        return 0 if not errors else 1

    ap = argparse.ArgumentParser(description="Run a hex image on the ISS")
    ap.add_argument("hex")
    ap.add_argument("--wait-states", type=int, default=0)
    ap.add_argument("--uart-in", default="")
    a = ap.parse_args(argv)
    st = ISS(load_hex(a.hex), a.wait_states, a.uart_in.encode()).run()
    print("regs:", " ".join(f"r{i}=0x{v:04x}" for i, v in enumerate(st.regs)))
    print(f"cycles={st.cycles} instret={st.instret} "
          f"CPI={st.cycles / max(st.instret, 1):.3f} halted={st.halted}")
    if st.uart_out:
        print("uart:", bytes(st.uart_out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
