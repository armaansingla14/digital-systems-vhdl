; sieve.asm - Sieve of Eratosthenes for primes below 128.
; Flags live at FLAGS[0..N-1]; primes are appended at PRIMES; r7 = count.
        .equ FLAGS, 0x300
        .equ PRIMES, 0x380
        .equ N, 128

start:  li   r1, FLAGS
        li   r2, 2              ; candidate i
        li   r6, PRIMES         ; output pointer
        li   r7, 0              ; prime count
outer:  li   r5, N
        beq  r2, r5, done
        add  r3, r1, r2
        lw   r4, 0(r3)          ; flags[i]
        bnez r4, nexti
        sw   r2, 0(r6)          ; i is prime
        inc  r6
        inc  r7
        add  r3, r2, r2         ; j = 2i
mark:   slt  r4, r3, r5         ; j < N ?
        beqz r4, nexti
        add  r4, r1, r3
        sw   r2, 0(r4)          ; mark composite (any non-zero value)
        add  r3, r3, r2
        j    mark
nexti:  inc  r2
        j    outer
done:   halt
