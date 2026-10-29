; hello.asm - print a string over the UART, wait for the transmitter to
; drain, then light a LED pattern and halt.
        .equ UART, 0xFF00       ; +0 DATA, +1 STATUS, +2 LEDS
        .equ TX_FULL, 1
        .equ TX_IDLE, 16

start:  li   r1, msg
        li   r2, UART
loop:   lw   r3, 0(r1)
        beqz r3, drain
txwait: lw   r4, 1(r2)
        li   r5, TX_FULL
        and  r4, r4, r5
        bnez r4, txwait
        sw   r3, 0(r2)
        inc  r1
        j    loop
drain:  lw   r4, 1(r2)
        li   r5, TX_IDLE
        and  r4, r4, r5
        beqz r4, drain
        li   r5, 0x55
        sw   r5, 2(r2)
        halt

msg:    .asciz "Hello from the VHDL CPU!\r\n"
