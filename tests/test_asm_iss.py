"""Host-side tests for the assembler and the instruction-set simulator."""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import asm  # noqa: E402
import iss  # noqa: E402


def run_src(src: str, **kw) -> iss.State:
    prog = asm.assemble_text(src)
    return iss.ISS(prog.image(), **kw).run()


def test_encodings():
    p = asm.assemble_text("""
        add r1, r2, r3
        addi r4, r5, -1
        lui r6, 0xAB
        lli r6, 0xCD
        lw r1, 3(r2)
        sw r1, -4(r2)
        jr r7
        nop
        halt
    """)
    assert p.image() == [
        0x0000 | (1 << 9) | (2 << 6) | (3 << 3) | 0,
        0x1000 | (4 << 9) | (5 << 6) | 0x3F,
        0x2000 | (6 << 9) | 0xAB,
        0x3000 | (6 << 9) | 0xCD,
        0x4000 | (1 << 9) | (2 << 6) | 3,
        0x5000 | (1 << 9) | (2 << 6) | 0x3C,
        0x9000 | (7 << 6),
        0xE000,
        0xF000,
    ]


def test_branch_offsets_and_labels():
    p = asm.assemble_text("""
    top:  nop
          beq r1, r2, top     ; offset -2
          bne r1, r0, fwd     ; offset +1
          nop
    fwd:  jal r7, top          ; offset -5
    """)
    img = p.image()
    assert img[1] & 0x3F == (-2) & 0x3F
    assert img[2] & 0x3F == 1
    assert img[4] & 0x1FF == (-5) & 0x1FF
    assert p.symbols["fwd"] == 4


def test_li_sizes():
    p = asm.assemble_text("li r1, 5\nli r2, -32\nli r3, 0x1234\nli r4, later\nlater: halt")
    img = p.image()
    assert len(img) == 1 + 1 + 2 + 2 + 1
    assert img[2] == 0x2000 | (3 << 9) | 0x12 and img[3] == 0x3000 | (3 << 9) | 0x34


def test_directives():
    p = asm.assemble_text('.org 0x10\nd: .word 1, -1, 0x8000\ns: .asciz "hi"\n.space 2\nend: halt')
    img = p.image()
    assert img[0x10:0x13] == [1, 0xFFFF, 0x8000]
    assert img[0x13:0x16] == [ord("h"), ord("i"), 0]
    assert p.symbols["end"] == 0x18


@pytest.mark.parametrize("src,msg", [
    ("addi r1, r1, 32", "out of range"),
    ("beq r1, r2, nowhere", "undefined"),
    ("add r1, r2", "expects 3"),
    ("x: nop\nx: nop", "duplicate"),
    ("lw r1, r2", "memory operand"),
    ("foo r1", "unknown"),
])
def test_errors(src, msg):
    with pytest.raises(asm.AsmError, match=msg):
        asm.assemble_text(src)


def test_alu_semantics():
    st = run_src("""
        li r1, 0x8000
        li r2, 1
        slt r3, r1, r2      ; signed: -32768 < 1
        sub r4, r0, r2      ; 0 - 1 = 0xFFFF
        li r5, 15
        srl r6, r4, r5      ; 1
        sll r7, r2, r5      ; 0x8000
        halt
    """)
    assert st.regs[3] == 1 and st.regs[4] == 0xFFFF
    assert st.regs[6] == 1 and st.regs[7] == 0x8000


def test_r0_is_zero_and_call_ret():
    st = run_src("""
        addi r0, r0, 5
        call f
        halt
    f:  addi r1, r0, 7
        ret
    """)
    assert st.regs[0] == 0 and st.regs[1] == 7 and st.regs[7] == 2


def test_cycle_model():
    # li(1 word) addi -> 5 cycles, sw ram -> 2+1+1+2 = 6, beq -> 4, halt -> 3
    st = run_src("addi r1, r0, 1\nsw r1, 0x10(r0)\nbeq r0, r0, next\nnext: halt")
    assert st.cycles == 5 + 6 + 4 + 3
    st2 = run_src("addi r1, r0, 1\nsw r1, 0x10(r0)\nbeq r0, r0, next\nnext: halt", wait_states=2)
    # 4 fetches + 1 RAM data access, each +2
    assert st2.cycles == st.cycles + 2 * 5


def test_uart_model():
    st = iss.ISS(asm.assemble_file(str(ROOT / "programs" / "echo.asm")).image(),
                 uart_in=b"ab.").run()
    assert bytes(st.uart_out) == b"AB."
    assert st.mem[0x300:0x303] == [ord("a"), ord("b"), ord(".")]


@pytest.mark.parametrize("name,check", [
    ("fib", lambda s: s.mem[0x200:0x218][:8] == [0, 1, 1, 2, 3, 5, 8, 13]),
    ("sort", lambda s: [iss.to_s16(v) for v in s.mem[0x100:0x110]] ==
        sorted([812, -5, 300, 7, 0x7FFF, 19, -300, 42, 0, 1000, 3, -32768, 77, 5, 64, 255])),
    ("sieve", lambda s: s.regs[7] == 31 and s.mem[0x380:0x385] == [2, 3, 5, 7, 11]),
    ("muldiv", lambda s: s.mem[0x180 + 4 * 4 + 2:0x180 + 4 * 4 + 4] == [(1071 * 462) & 0xFFFF, 21]),
    ("hello", lambda s: bytes(s.uart_out) == b"Hello from the VHDL CPU!\r\n" and s.leds == 0x55),
])
def test_programs(name, check):
    st = iss.ISS(asm.assemble_file(str(ROOT / "programs" / f"{name}.asm")).image()).run()
    assert st.halted and not st.illegal
    assert check(st)


def test_isa_program_values():
    st = iss.ISS(asm.assemble_file(str(ROOT / "programs" / "isa_test.asm")).image()).run()
    out = st.mem[0x200:0x213]
    a, b = 0x1234, 0xF00F
    assert out[0] == (a + b) & 0xFFFF and out[1] == (a - b) & 0xFFFF
    assert out[5] == 1 and out[6] == 0 and out[11] == 0
    assert out[15] == 6 and out[16] == 42 and out[18] == 0x600D
