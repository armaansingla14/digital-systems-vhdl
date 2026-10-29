; echo.asm - receive characters over the UART, convert a-z to upper case
; and transmit them back until a '.' has been echoed. Received bytes
; are also logged to a buffer in RAM.
        .equ UART, 0xFF00
        .equ TX_FULL, 1
        .equ RX_AVAIL, 4
        .equ TX_IDLE, 16
        .equ BUF, 0x300

start:  li   r2, UART
        li   r6, BUF
rxwait: lw   r4, 1(r2)
        li   r5, RX_AVAIL
        and  r4, r4, r5
        beqz r4, rxwait
        lw   r3, 0(r2)          ; pop RX FIFO
        sw   r3, 0(r6)
        inc  r6
        li   r5, 'a'
        slt  r4, r3, r5
        bnez r4, txwait
        li   r5, 'z'+1
        slt  r4, r3, r5
        beqz r4, txwait
        addi r3, r3, -32
txwait: lw   r4, 1(r2)
        li   r5, TX_FULL
        and  r4, r4, r5
        bnez r4, txwait
        sw   r3, 0(r2)
        li   r5, '.'
        bne  r3, r5, rxwait
drain:  lw   r4, 1(r2)
        li   r5, TX_IDLE
        and  r4, r4, r5
        beqz r4, drain
        halt
