; isa_test.asm - touches every opcode and ALU function, including edge
; cases (r0 writes, negative immediates, shifts by 0/15, signed compare,
; taken and not-taken branches, JAL/JR linkage). Results are stored to
; consecutive words at 0x200 and checked against the ISS.
        .equ OUT, 0x200

start:  li   r6, OUT
        li   r1, 0x1234
        li   r2, 0xF00F
        add  r3, r1, r2
        sw   r3, 0(r6)
        sub  r3, r1, r2
        sw   r3, 1(r6)
        and  r3, r1, r2
        sw   r3, 2(r6)
        or   r3, r1, r2
        sw   r3, 3(r6)
        xor  r3, r1, r2
        sw   r3, 4(r6)
        slt  r3, r2, r1         ; negative < positive -> 1
        sw   r3, 5(r6)
        slt  r3, r1, r2         ; -> 0
        sw   r3, 6(r6)
        li   r4, 15
        sll  r3, r1, r4
        sw   r3, 7(r6)
        srl  r3, r2, r4
        sw   r3, 8(r6)
        sll  r3, r1, r0         ; shift by zero
        sw   r3, 9(r6)
        addi r3, r1, -32
        sw   r3, 10(r6)
        addi r0, r1, 5          ; write to r0 is ignored
        sw   r0, 11(r6)
        lui  r3, 0xAB
        sw   r3, 12(r6)
        lli  r3, 0xCD
        sw   r3, 13(r6)
        lw   r5, 12(r6)         ; load back
        addi r5, r5, 1
        sw   r5, 14(r6)
        ; branches
        li   r3, 0
        beq  r1, r1, b1
        addi r3, r3, 1          ; skipped
b1:     bne  r1, r1, b2         ; not taken
        addi r3, r3, 2
b2:     beq  r1, r2, b3         ; not taken
        addi r3, r3, 4
b3:     bne  r1, r2, b4         ; taken
        addi r3, r3, 8          ; skipped
b4:     sw   r3, 15(r6)         ; expect 6
        ; jal / jr
        call sub1
        sw   r3, 16(r6)
        sw   r7, 17(r6)         ; return address
        li   r4, after
        jr   r4
        halt                    ; skipped
after:  nop
        li   r3, 0x600D
        sw   r3, 18(r6)
        halt

sub1:   addi r3, r0, 21
        add  r3, r3, r3
        ret
