#!/usr/bin/env python3
"""Two-pass assembler for the 16-bit multi-cycle CPU.

Usage:
    python3 tools/asm.py programs/fib.asm -o build/fib.hex [-l build/fib.lst]

Syntax summary
--------------
    label:                     define a label at the current address
    add rd, rs1, rs2           R-type: add sub and or xor slt sll srl
    addi rd, rs1, imm6         rd = rs1 + sext(imm6)
    lui rd, imm8               rd = imm8 << 8
    lli rd, imm8               rd = (rd & 0xFF00) | imm8
    lw rd, off(rs1)            rd = mem[rs1 + sext(off)]
    sw rs, off(rs1)            mem[rs1 + sext(off)] = rs
    beq ra, rb, label          branch if ra == rb (PC-relative, +-32)
    bne ra, rb, label
    jal rd, label              rd = pc + 1; pc = label (PC-relative, +-256)
    jr rs                      pc = rs
    nop / halt

Pseudo-instructions: li rd, imm16 | mov rd, rs | j label | call label |
ret | beqz rs, label | bnez rs, label | inc rd | dec rd
Directives: .org addr | .word v, ... | .equ name, v | .ascii "s" |
.asciz "s" | .space n

Comments start with ';' or '#'. Numbers may be decimal, 0x-hex, 0b-binary
or a quoted character such as 'A'.
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field

MEM_WORDS = 4096

OPCODES = {
    "alu": 0x0, "addi": 0x1, "lui": 0x2, "lli": 0x3, "lw": 0x4, "sw": 0x5,
    "beq": 0x6, "bne": 0x7, "jal": 0x8, "jr": 0x9, "nop": 0xE, "halt": 0xF,
}
FUNCTS = {"add": 0, "sub": 1, "and": 2, "or": 3, "xor": 4, "slt": 5,
          "sll": 6, "srl": 7}


class AsmError(Exception):
    def __init__(self, msg: str, line: int | None = None):
        super().__init__(f"line {line}: {msg}" if line else msg)


@dataclass
class Stmt:
    line: int
    addr: int
    mnemonic: str
    args: list[str]
    size: int
    source: str


@dataclass
class Program:
    words: dict[int, int] = field(default_factory=dict)
    symbols: dict[str, int] = field(default_factory=dict)
    listing: list[str] = field(default_factory=list)

    def image(self) -> list[int]:
        if not self.words:
            return []
        top = max(self.words) + 1
        return [self.words.get(a, 0) for a in range(top)]


def parse_reg(tok: str, line: int) -> int:
    tok = tok.strip().lower()
    m = re.fullmatch(r"r([0-7])", tok)
    if not m:
        raise AsmError(f"bad register '{tok}'", line)
    return int(m.group(1))


def split_args(text: str) -> list[str]:
    out, cur, quote = [], "", None
    for ch in text:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            cur += ch
        elif ch == ",":
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def strip_comment(text: str) -> str:
    quote = None
    for i, ch in enumerate(text):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch in ";#":
            return text[:i]
    return text


class Assembler:
    def __init__(self) -> None:
        self.symbols: dict[str, int] = {}

    # -- expression evaluation -------------------------------------------
    def value(self, tok: str, line: int, allow_undefined: bool = False) -> int | None:
        tok = tok.strip()
        terms = re.split(r"(?=[+-])", tok.replace(" ", ""))
        total = 0
        for term in terms:
            if not term:
                continue
            sign = -1 if term.startswith("-") else 1
            body = term.lstrip("+-")
            if re.fullmatch(r"'.'", body):
                v = ord(body[1])
            elif re.fullmatch(r"0[xX][0-9a-fA-F]+", body):
                v = int(body, 16)
            elif re.fullmatch(r"0[bB][01]+", body):
                v = int(body, 2)
            elif re.fullmatch(r"\d+", body):
                v = int(body)
            elif re.fullmatch(r"[A-Za-z_.][\w.]*", body):
                if body not in self.symbols:
                    if allow_undefined:
                        return None
                    raise AsmError(f"undefined symbol '{body}'", line)
                v = self.symbols[body]
            else:
                raise AsmError(f"bad expression '{tok}'", line)
            total += sign * v
        return total

    @staticmethod
    def check_range(v: int, bits: int, signed: bool, what: str, line: int) -> int:
        lo, hi = (-(1 << (bits - 1)), (1 << (bits - 1)) - 1) if signed else (0, (1 << bits) - 1)
        if not lo <= v <= hi:
            raise AsmError(f"{what} {v} out of range [{lo}, {hi}]", line)
        return v & ((1 << bits) - 1)

    # -- pass 1 ------------------------------------------------------------
    def stmt_size(self, mn: str, args: list[str], line: int) -> int:
        if mn == "li":
            v = self.value(args[1], line, allow_undefined=True)
            if v is not None and -32 <= v <= 31:
                return 1
            return 2
        if mn == ".word":
            return len(args)
        if mn in (".ascii", ".asciz"):
            s = self.string_arg(args, line)
            return len(s) + (1 if mn == ".asciz" else 0)
        if mn == ".space":
            return self.value(args[0], line)
        return 1

    @staticmethod
    def string_arg(args: list[str], line: int) -> str:
        if len(args) != 1 or not re.fullmatch(r'".*"', args[0]):
            raise AsmError("expected a quoted string", line)
        return bytes(args[0][1:-1], "utf-8").decode("unicode_escape")

    def assemble(self, source: str) -> Program:
        stmts: list[Stmt] = []
        pc = 0
        for lineno, raw in enumerate(source.splitlines(), start=1):
            text = strip_comment(raw).strip()
            while True:
                m = re.match(r"^([A-Za-z_.][\w.]*):\s*(.*)$", text)
                if not m:
                    break
                name = m.group(1)
                if name in self.symbols:
                    raise AsmError(f"duplicate label '{name}'", lineno)
                self.symbols[name] = pc
                text = m.group(2)
            if not text:
                continue
            parts = text.split(None, 1)
            mn = parts[0].lower()
            args = split_args(parts[1]) if len(parts) > 1 else []
            if mn == ".org":
                pc = self.value(args[0], lineno)
                continue
            if mn == ".equ":
                self.symbols[args[0]] = self.value(args[1], lineno)
                continue
            size = self.stmt_size(mn, args, lineno)
            stmts.append(Stmt(lineno, pc, mn, args, size, raw.rstrip()))
            pc += size
            if pc > MEM_WORDS:
                raise AsmError("program exceeds memory", lineno)

        prog = Program(symbols=dict(self.symbols))
        for st in stmts:
            words = self.encode(st)
            if len(words) != st.size:
                raise AsmError("internal size mismatch", st.line)
            for i, w in enumerate(words):
                if st.addr + i in prog.words:
                    raise AsmError(f"overlapping code at 0x{st.addr + i:03x}", st.line)
                prog.words[st.addr + i] = w
            hexs = " ".join(f"{w:04x}" for w in words[:4])
            prog.listing.append(f"{st.addr:04x}  {hexs:<20s} {st.source.strip()}")
        return prog

    # -- pass 2 ------------------------------------------------------------
    def encode(self, st: Stmt) -> list[int]:
        mn, a, ln = st.mnemonic, st.args, st.line

        def need(n: int) -> None:
            if len(a) != n:
                raise AsmError(f"'{mn}' expects {n} operands, got {len(a)}", ln)

        def r_type(funct: int, rd: int, rs1: int, rs2: int) -> int:
            return (OPCODES["alu"] << 12) | (rd << 9) | (rs1 << 6) | (rs2 << 3) | funct

        def i_type(op: str, rd: int, rs1: int, imm: int) -> int:
            return (OPCODES[op] << 12) | (rd << 9) | (rs1 << 6) | \
                self.check_range(imm, 6, True, "immediate", ln)

        def u_type(op: str, rd: int, imm: int) -> int:
            return (OPCODES[op] << 12) | (rd << 9) | self.check_range(imm, 8, False, "imm8", ln)

        def branch(op: str, ra: int, rb: int, target: str) -> int:
            off = self.value(target, ln) - (st.addr + 1)
            # BEQ/BNE encode the first compared register in [11:9] and the
            # second in [8:6].
            return (OPCODES[op] << 12) | (ra << 9) | (rb << 6) | \
                self.check_range(off, 6, True, "branch offset", ln)

        def jal(rd: int, target: str) -> int:
            off = self.value(target, ln) - (st.addr + 1)
            return (OPCODES["jal"] << 12) | (rd << 9) | \
                self.check_range(off, 9, True, "jump offset", ln)

        def mem_operand(text: str) -> tuple[int, int]:
            m = re.fullmatch(r"\s*(.*)\(\s*(r[0-7])\s*\)\s*", text, re.I)
            if not m:
                raise AsmError(f"bad memory operand '{text}'", ln)
            off = self.value(m.group(1), ln) if m.group(1).strip() else 0
            return off, parse_reg(m.group(2), ln)

        if mn in FUNCTS:
            need(3)
            return [r_type(FUNCTS[mn], parse_reg(a[0], ln), parse_reg(a[1], ln), parse_reg(a[2], ln))]
        if mn == "addi":
            need(3)
            return [i_type("addi", parse_reg(a[0], ln), parse_reg(a[1], ln), self.value(a[2], ln))]
        if mn in ("lui", "lli"):
            need(2)
            return [u_type(mn, parse_reg(a[0], ln), self.value(a[1], ln))]
        if mn in ("lw", "sw"):
            need(2)
            off, base = mem_operand(a[1])
            return [i_type(mn, parse_reg(a[0], ln), base, off)]
        if mn in ("beq", "bne"):
            need(3)
            return [branch(mn, parse_reg(a[0], ln), parse_reg(a[1], ln), a[2])]
        if mn == "jal":
            need(2)
            return [jal(parse_reg(a[0], ln), a[1])]
        if mn == "jr":
            need(1)
            return [(OPCODES["jr"] << 12) | (parse_reg(a[0], ln) << 6)]
        if mn in ("nop", "halt"):
            need(0)
            return [OPCODES[mn] << 12]
        # pseudo-instructions
        if mn == "li":
            need(2)
            rd, v = parse_reg(a[0], ln), self.value(a[1], ln)
            if not -32768 <= v <= 0xFFFF:
                raise AsmError(f"li value {v} out of 16-bit range", ln)
            v &= 0xFFFF
            if st.size == 1:
                return [i_type("addi", rd, 0, v - 0x10000 if v & 0x8000 else v)]
            return [u_type("lui", rd, v >> 8), u_type("lli", rd, v & 0xFF)]
        if mn == "mov":
            need(2)
            return [i_type("addi", parse_reg(a[0], ln), parse_reg(a[1], ln), 0)]
        if mn == "inc":
            need(1)
            r = parse_reg(a[0], ln)
            return [i_type("addi", r, r, 1)]
        if mn == "dec":
            need(1)
            r = parse_reg(a[0], ln)
            return [i_type("addi", r, r, -1)]
        if mn == "j":
            need(1)
            return [jal(0, a[0])]
        if mn == "call":
            need(1)
            return [jal(7, a[0])]
        if mn == "ret":
            need(0)
            return [(OPCODES["jr"] << 12) | (7 << 6)]
        if mn in ("beqz", "bnez"):
            need(2)
            return [branch("beq" if mn == "beqz" else "bne", parse_reg(a[0], ln), 0, a[1])]
        if mn == ".word":
            return [self.value(x, ln) & 0xFFFF for x in a]
        if mn in (".ascii", ".asciz"):
            s = self.string_arg(a, ln)
            return [ord(c) & 0xFF for c in s] + ([0] if mn == ".asciz" else [])
        if mn == ".space":
            return [0] * self.value(a[0], ln)
        raise AsmError(f"unknown mnemonic '{mn}'", ln)


def assemble_text(source: str) -> Program:
    return Assembler().assemble(source)


def assemble_file(path: str) -> Program:
    with open(path, encoding="utf-8") as f:
        return assemble_text(f.read())


def write_hex(prog: Program, path: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        for w in prog.image():
            f.write(f"{w:04X}\n")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("source")
    ap.add_argument("-o", "--output", required=True, help="hex output file")
    ap.add_argument("-l", "--listing", help="optional listing file")
    args = ap.parse_args(argv)
    try:
        prog = assemble_file(args.source)
    except AsmError as e:
        print(f"{args.source}: {e}", file=sys.stderr)
        return 1
    write_hex(prog, args.output)
    if args.listing:
        with open(args.listing, "w", encoding="utf-8") as f:
            f.write("\n".join(prog.listing) + "\n")
    print(f"{args.source}: {len(prog.image())} words -> {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
