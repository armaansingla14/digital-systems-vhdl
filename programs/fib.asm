; fib.asm - store Fibonacci numbers F(0)..F(23) at 0x200
        .equ OUT, 0x200
        .equ N, 24

start:  li   r1, OUT            ; output pointer
        li   r2, 0              ; F(n)
        li   r3, 1              ; F(n+1)
        li   r4, N              ; remaining terms
loop:   sw   r2, 0(r1)
        add  r5, r2, r3
        mov  r2, r3
        mov  r3, r5
        inc  r1
        dec  r4
        bnez r4, loop
        halt
