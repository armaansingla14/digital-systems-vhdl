#!/usr/bin/env python3
"""Build and run every GHDL testbench, then cross-check the CPU programs
against the instruction-set simulator.

Intended to run inside the devtools container (see Makefile):
    python3 scripts/run_tests.py [--waves] [--only NAME ...]

Writes results/testbench_results.md and results/testbench_results.csv.
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import asm  # noqa: E402
import iss  # noqa: E402

BUILD = ROOT / "build"
RESULTS = ROOT / "results"
GHDL = ["ghdl"]
STD = ["--std=08", f"--workdir={BUILD}"]

RTL = ["cpu_pkg", "alu", "regfile", "counter", "fifo", "control_unit",
       "datapath", "cpu", "sync_sram", "sram_ctrl", "baud_gen", "uart_tx",
       "uart_rx", "uart_ctrl", "soc_top", "fpga_top"]
TBS = ["tb_pkg", "tb_alu", "tb_regfile", "tb_counter", "tb_fifo", "tb_uart",
       "tb_sram_ctrl", "tb_soc"]

# (run name, testbench entity, generics)
UNIT_RUNS = [
    ("tb_alu", "tb_alu", {}),
    ("tb_regfile", "tb_regfile", {}),
    ("tb_counter", "tb_counter", {}),
    ("tb_fifo", "tb_fifo", {}),
    ("tb_uart", "tb_uart", {"DIVISOR": 2}),
    ("tb_sram_ctrl_ws0", "tb_sram_ctrl", {"WAIT_STATES": 0}),
    ("tb_sram_ctrl_ws3", "tb_sram_ctrl", {"WAIT_STATES": 3}),
]

# (program, wait states, uart input, compare cycles exactly?)
PROGRAM_RUNS = [
    ("isa_test", 0, "", True),
    ("fib", 0, "", True),
    ("fib", 2, "", True),
    ("sort", 0, "", True),
    ("sort", 3, "", True),
    ("muldiv", 0, "", True),
    ("sieve", 0, "", True),
    ("sieve", 1, "", True),
    ("hello", 0, "", False),
    ("echo", 0, "Hello, vhdl world.", False),
]

TB_RE = re.compile(r"TB_RESULT (\S+) checks=(\d+) failures=(\d+) cycles=(\d+) status=(\w+)")


@dataclass
class Row:
    name: str
    checks: int
    failures: int
    sim_cycles: int
    status: str
    seconds: float
    note: str = ""


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)


def analyze() -> None:
    BUILD.mkdir(exist_ok=True)
    for name in RTL:
        p = run(GHDL + ["-a"] + STD + [f"rtl/{name}.vhd"])
        if p.returncode:
            sys.exit(f"analysis failed: rtl/{name}.vhd\n{p.stderr}")
    for name in TBS:
        p = run(GHDL + ["-a"] + STD + [f"tb/{name}.vhd"])
        if p.returncode:
            sys.exit(f"analysis failed: tb/{name}.vhd\n{p.stderr}")
    for ent in sorted({tb for _, tb, _ in UNIT_RUNS} | {"tb_soc"}):
        p = run(GHDL + ["-e"] + STD + [ent])
        if p.returncode:
            sys.exit(f"elaboration failed: {ent}\n{p.stderr}")


def sim(entity: str, generics: dict, waves: str | None) -> tuple[subprocess.CompletedProcess, float]:
    cmd = GHDL + ["-r"] + STD + [entity]
    cmd += [f"-g{k}={v}" for k, v in generics.items()]
    if waves:
        cmd.append(f"--wave={waves}")
    cmd.append("--stop-time=100ms")  # watchdog: a hung testbench fails instead of spinning
    t0 = time.perf_counter()
    p = run(cmd, timeout=300)
    return p, time.perf_counter() - t0


def parse_tb(out: str, name: str, secs: float) -> Row:
    m = TB_RE.search(out)
    if not m:
        return Row(name, 0, 1, 0, "FAIL", secs, "no TB_RESULT line")
    return Row(name, int(m.group(2)), int(m.group(3)), int(m.group(4)),
               m.group(5), secs)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--waves", action="store_true", help="write build/*.ghw")
    ap.add_argument("--only", nargs="*", help="run only these run names")
    args = ap.parse_args()

    analyze()
    unit_rows: list[Row] = []
    for name, ent, gens in UNIT_RUNS:
        if args.only and name not in args.only:
            continue
        p, secs = sim(ent, gens, str(BUILD / f"{name}.ghw") if args.waves else None)
        row = parse_tb(p.stdout + p.stderr, name, secs)
        if p.returncode and row.status == "PASS":
            row.status, row.note = "FAIL", f"exit code {p.returncode}"
        unit_rows.append(row)
        print(f"{name:22s} {row.status} checks={row.checks} cycles={row.sim_cycles} ({secs:.1f}s)")
        if row.status != "PASS":
            print(p.stdout[-3000:], p.stderr[-3000:])

    prog_rows = []
    for prog, ws, uart_in, exact in PROGRAM_RUNS:
        name = f"{prog}_ws{ws}"
        if args.only and name not in args.only:
            continue
        hex_path = BUILD / f"{prog}.hex"
        program = asm.assemble_file(str(ROOT / "programs" / f"{prog}.asm"))
        asm.write_hex(program, str(hex_path))
        (BUILD / f"{prog}.lst").write_text("\n".join(program.listing) + "\n")
        dump = BUILD / f"{name}.dump"
        gens = {"PROG_FILE": hex_path, "DUMP_FILE": dump, "TB_NAME": f"soc_{name}",
                "WAIT_STATES": ws}
        if uart_in:
            gens["UART_IN"] = uart_in
        if dump.exists():
            dump.unlink()
        p, secs = sim("tb_soc", gens, str(BUILD / f"soc_{name}.ghw") if args.waves else None)
        row = parse_tb(p.stdout + p.stderr, f"soc_{name}", secs)
        if not dump.exists():
            print(f"soc_{name}: no dump written\n{p.stdout[-3000:]}{p.stderr[-3000:]}")
            unit_rows.append(Row(f"soc_{name}", row.checks, max(row.failures, 1),
                                 row.sim_cycles, "FAIL", secs, "no dump"))
            continue
        errors, d, st = iss.compare(str(hex_path), str(dump), ws, uart_in.encode(), exact)
        status = "PASS" if row.status == "PASS" and not errors else "FAIL"
        prog_rows.append({
            "program": prog, "wait_states": ws, "words": len(program.image()),
            "rtl_cycles": d.get("cycles"), "iss_cycles": st.cycles,
            "cycle_check": "exact" if exact else "n/a (I/O polling)",
            "instret": d.get("instret"),
            "cpi": round(d.get("cycles", 0) / max(d.get("instret", 1), 1), 3),
            "tb_checks": row.checks, "iss_checks": d["checks"],
            "uart_out": bytes(d["uart"]).decode("latin-1"),
            "status": status, "seconds": round(secs, 2),
        })
        unit_rows.append(Row(f"soc_{name}", row.checks + d["checks"],
                             row.failures + len(errors), row.sim_cycles, status, secs,
                             "TB + ISS checks"))
        print(f"soc_{name:17s} {status} rtl_cycles={d.get('cycles')} iss_cycles={st.cycles} "
              f"instret={d.get('instret')} uart={bytes(d['uart'])!r}")
        for e in errors:
            print("   ", e)
        if row.status != "PASS":
            print(p.stdout[-3000:], p.stderr[-3000:])

    RESULTS.mkdir(exist_ok=True)
    if not args.only and prog_rows:
        write_results(unit_rows, prog_rows)
    failed = [r.name for r in unit_rows if r.status != "PASS"]
    total_checks = sum(r.checks for r in unit_rows)
    total_cycles = sum(r.sim_cycles for r in unit_rows)
    print(f"\n{len(unit_rows) - len(failed)}/{len(unit_rows)} runs passed, "
          f"{total_checks} checks, {total_cycles} simulated clock cycles")
    return 1 if failed else 0


def write_results(rows: list[Row], progs: list[dict]) -> None:
    ver = run(["ghdl", "--version"]).stdout.splitlines()[0]
    with open(RESULTS / "testbench_results.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["run", "checks", "failures", "sim_cycles", "status", "wall_s", "note"])
        for r in rows:
            w.writerow([r.name, r.checks, r.failures, r.sim_cycles, r.status,
                        f"{r.seconds:.2f}", r.note])
    with open(RESULTS / "cpu_programs.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(progs[0].keys()))
        w.writeheader()
        w.writerows(progs)
    lines = [
        "# Simulation results",
        "",
        f"Generated by `scripts/run_tests.py` with {ver}.",
        "All numbers are from RTL simulation; nothing here was run on hardware.",
        "",
        "## Testbenches",
        "",
        "| Run | Checks | Failures | Simulated clock cycles | Status |",
        "|---|---:|---:|---:|---|",
    ]
    for r in rows:
        lines.append(f"| {r.name} | {r.checks} | {r.failures} | {r.sim_cycles} | {r.status} |")
    lines += [
        "",
        f"Total: {sum(r.checks for r in rows)} checks, "
        f"{sum(r.failures for r in rows)} failures, "
        f"{sum(r.sim_cycles for r in rows)} simulated clock cycles "
        "(tb_alu is combinational and reports 0 cycles).",
        "",
        "## CPU programs (RTL vs instruction-set simulator)",
        "",
        "| Program | SRAM wait states | Words | RTL cycles | ISS cycles | Cycle check | Instructions | CPI | Status |",
        "|---|---:|---:|---:|---:|---|---:|---:|---|",
    ]
    for p in progs:
        lines.append(f"| {p['program']} | {p['wait_states']} | {p['words']} | {p['rtl_cycles']} | "
                     f"{p['iss_cycles']} | {p['cycle_check']} | {p['instret']} | {p['cpi']} | {p['status']} |")
    uart = [p for p in progs if p["uart_out"]]
    if uart:
        lines += ["", "UART output captured by the testbench:", ""]
        for p in uart:
            lines.append(f"- `{p['program']}`: `{p['uart_out'].encode('unicode_escape').decode()}`")
    (RESULTS / "testbench_results.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
