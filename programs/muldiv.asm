; muldiv.asm - subroutine calls: shift-add multiply and subtractive GCD.
; Each table record is {a, b, a*b mod 2^16, gcd(a, b)}.

start:  li   r6, table
next:   li   r4, table_end
        beq  r6, r4, done
        lw   r1, 0(r6)
        lw   r2, 1(r6)
        call mul16
        sw   r3, 2(r6)
        lw   r1, 0(r6)
        lw   r2, 1(r6)
        call gcd
        sw   r1, 3(r6)
        addi r6, r6, 4
        j    next
done:   halt

; r3 = r1 * r2 (low 16 bits). Clobbers r1, r2, r4, r5.
mul16:  li   r3, 0
        li   r5, 1
mloop:  beqz r2, mdone
        and  r4, r2, r5
        beqz r4, mskip
        add  r3, r3, r1
mskip:  add  r1, r1, r1
        srl  r2, r2, r5
        j    mloop
mdone:  ret

; r1 = gcd(r1, r2) for 0 < r1, r2 < 32768. Clobbers r2, r4.
gcd:    beq  r1, r2, gdone
        slt  r4, r1, r2
        bnez r4, gless
        sub  r1, r1, r2
        j    gcd
gless:  sub  r2, r2, r1
        j    gcd
gdone:  ret

        .org 0x180
table:  .word 3, 5, 0, 0
        .word 12, 18, 0, 0
        .word 255, 255, 0, 0
        .word 1000, 37, 0, 0
        .word 1071, 462, 0, 0
        .word 300, 7, 0, 0
        .word 4096, 48, 0, 0
        .word 360, 84, 0, 0
table_end:
