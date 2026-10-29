; sort.asm - in-place bubble sort of 16 signed words at 'data'
        .equ N, 16

start:  li   r6, data           ; base address
        li   r1, N-1            ; passes remaining
outer:  mov  r2, r6             ; element pointer
        mov  r3, r1             ; comparisons in this pass
inner:  lw   r4, 0(r2)
        lw   r5, 1(r2)
        slt  r7, r5, r4         ; r7 = next < current (signed)
        beqz r7, noswap
        sw   r5, 0(r2)
        sw   r4, 1(r2)
noswap: inc  r2
        dec  r3
        bnez r3, inner
        dec  r1
        bnez r1, outer
        halt

        .org 0x100
data:   .word 812, -5, 300, 7, 0x7FFF, 19, -300, 42
        .word 0, 1000, 3, -32768, 77, 5, 64, 255
