/******************************************************************************
 * \file stat.S
 *
 * \brief Modified Z80 Status Messages for Linux
 *
 * \author Scott K Logan
 ******************************************************************************/

        .data

smsg:   .ascii "STAT:    A    B    C    D    E    F    H    L   PC   IL   SP (PC) FLAG\n"
rmsg:   .ascii "REG: "
emsg:   .ascii "\n----------------------------------------------------------------------\n"
hexch:  .ascii "0123456789ABCDEF"
nimsg:  .ascii ": This opcode is not implemented\n"

        .text

        .global opcode_not_implemented
opcode_not_implemented:
        stmfd sp!, {r7, lr}

        cmp r0, $0x00FF
        andgt r0, $0x00FF
        orrge r0, $0xCB00

        bl hex_print

        mov r0, $1
        ldr r1, =nimsg
        mov r2, $33
        mov r7, $4
        swi $0

        ldmfd sp!, {r7, pc}

        .global stat_print
stat_print:
        stmfd sp!, {r5-r7, lr}

        mov r5, r1
        mov r6, r0

        mov r0, $1
        ldr r1, =smsg
        mov r2, $71
        mov r7, $4
        swi $0

        mov r0, $1
        ldr r1, =rmsg
        mov r2, $5
        mov r7, $4
        swi $0

        @ zra
        ldr r0, [r6, $4]
        bl hex_print

        @ zrb
        ldr r0, [r6, $8]
        bl hex_print

        @ zrc
        ldr r0, [r6, $12]
        bl hex_print

        @ zrd
        ldr r0, [r6, $16]
        bl hex_print

        @ zre
        ldr r0, [r6, $20]
        bl hex_print

        @ zrf
        ldr r0, [r6, $24]
        bl hex_print

        @ zrh
        ldr r0, [r6, $28]
        bl hex_print

        @ zrl
        ldr r0, [r6, $32]
        bl hex_print

        @ zpc
        ldr r0, [r6, $36]
        bl hex_print

        @ zil
        ldr r0, [r6, $40]
        bl hex_print

        @ zpc
        ldr r0, [r6, $44]
        bl hex_print

        @ (zpc)
        mov r0, r5
        bl hex_print

        @ flags
        sub sp, $5
        mov r1, $' '
        strb r1, [sp]
        ldr r0, [r6, $24]

        @ flZ
        tst r0, $0x80
        movne r1, $'Z'
        moveq r1, $'z'
        strb r1, [sp, $1]

        @ flN
        tst r0, $0x40
        movne r1, $'N'
        moveq r1, $'n'
        strb r1, [sp, $2]

        @ flH
        tst r0, $0x20
        movne r1, $'H'
        moveq r1, $'h'
        strb r1, [sp, $3]

        @ flC
        tst r0, $0x10
        movne r1, $'C'
        moveq r1, $'c'
        strb r1, [sp, $4]

        mov r0, $1
        mov r1, sp
        mov r2, $5
        mov r7, $4
        swi $0

        add sp, $5

        mov r0, $1
        ldr r1, =emsg
        mov r2, $72
        mov r7, $4
        swi $0

        ldmfd sp!, {r5-r7, pc}

hex_print:
        stmfd sp!, {r7}
        sub sp, $5

        mov r1, $' '
        strb r1, [sp]

        ldr r2, =hexch

        @ First nibble
        mov r1, r0
        and r1, $0xF
        ldrb r1, [r2, r1]
        strb r1, [sp, $4]

        @ Second nibble
        mov r1, r0, lsr $4
        and r1, $0xF
        ldrb r1, [r2, r1]
        strb r1, [sp, $3]

        @ Third nibble
        mov r1, r0, lsr $8
        and r1, $0xF
        ldrb r1, [r2, r1]
        strb r1, [sp, $2]

        @ Fourth nibble
        mov r1, r0, lsr $12
        and r1, $0xF
        ldrb r1, [r2, r1]
        strb r1, [sp, $1]

        mov r0, $1
        mov r1, sp
        mov r2, $5
        mov r7, $4
        swi $0

        add sp, $5
        ldmfd sp!, {r7}
        mov pc, lr
