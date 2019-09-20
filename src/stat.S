/******************************************************************************
 * \file stat.S
 *
 * \copyright
 * Copyright &copy; 2016, Scott K Logan
 *
 * \copyright
 * All rights reserved.
 *
 * \copyright
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * \copyright
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * * Neither the name of the copyright holder nor the names of its contributors
 *   may be used to endorse or promote products derived from this software
 *   without specific prior written permission.
 *
 * \copyright
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * \brief Modified Z80 Status Messages for Linux
 *
 * \author Scott K Logan
 ******************************************************************************/

        .text

smsg:   .ascii "   A    B    C    D    E    F   HL   SP   PC  (PC) FLAG  IC   TC   GC   GL   IF   IE  TMAC\n"
smsg_e: .align
emsg:   .ascii "\n------------------------------------------------------------------------------------------\n"
emsg_e: .align
hexch:  .ascii "0123456789ABCDEF"
        .align
nimsg:  .ascii "A CPU exception has occurred\n\n"
        .align

        .global stat_cpu_exception
stat_cpu_exception:
        stmfd sp!, {r2, r7}

        mov r0, $0x01
        ldr r1, =nimsg
        mov r2, $0x1E
        mov r7, $0x04
        svc $0

        ldmfd sp!, {r2, r7}
        mov pc, lr

        .global stat_print
stat_print:
        stmfd sp!, {r2-r8, lr}

        mov r8, sp
        sub sp, $255
        sub sp, $35
        mov r7, sp

        /* Copy in smsg (85 bytes) */
        ldr r0, =smsg
        ldmia r0!, {r1-r6}
        stmia r7!, {r1-r6}
        ldmia r0!, {r1-r6}
        stmia r7!, {r1-r6}
        ldmia r0!, {r1-r6}
        stmia r7!, {r1-r6}
        ldmia r0!, {r1-r4}
        stmia r7!, {r1-r4}
        ldr r1, [r0]
        str r1, [r7]
        add r7, $0x03

        @ zra
        ldr r0, [r8, $4]
        bl hex_print

        @ zrb
        ldr r0, [r8, $8]
        bl hex_print

        @ zrc
        ldr r0, [r8, $12]
        bl hex_print

        @ zrd
        ldr r0, [r8, $16]
        bl hex_print

        @ zre
        ldr r0, [r8, $20]
        bl hex_print

        @ zrf
        ldr r0, [r8, $24]
        bl hex_print

        @ zhl
        lsr r0, r9, $0x10
        bl hex_print

        @ zsp
        lsr r0, r10, $0x10
        bl hex_print

        @ zpc
        lsr r0, r11, $0x10
        bl hex_print

        @ (zpc)
        lsr r0, r11, $0x10
        bl mmu_rb
        mov r2, r0

        add r0, r11, $0x00010000
        lsr r0, $0x10
        bl mmu_rb
        orr r0, r2, lsl $0x08

        bl hex_print

        @ flags
        mov r0, $' '
        strb r0, [r7]
        ldr r0, [r8, $24]

        @ flZ
        tst r0, $0x80
        movne r2, $'Z'
        moveq r2, $'z'
        strb r2, [r7, $1]

        @ flN
        tst r0, $0x40
        movne r2, $'N'
        moveq r2, $'n'
        strb r2, [r7, $2]

        @ flH
        tst r0, $0x20
        movne r2, $'H'
        moveq r2, $'h'
        strb r2, [r7, $3]

        @ flC
        tst r0, $0x10
        movne r2, $'C'
        moveq r2, $'c'
        strb r2, [r7, $4]

        add r7, $5

        @ ic
        and r0, r12, $0x07
        bl hex_print

        @ tc
        and r0, r12, $0x18
        lsr r0, $3
        bl hex_print

        @ gc
        lsl r0, r12, $0x13
        lsr r0, $0x18
        rsb r0, $0x80
        bl hex_print

        @ gl
        lsl r0, r12, $0x09
        lsr r0, $0x18
        bl hex_print

        @ if
        mov r0, $0xFF00
        orr r0, $0x000F
        bl mmu_rb
        bl hex_print

        @ ie
        mov r0, $0xFF00
        orr r0, $0x00FF
        bl mmu_rb
        bl hex_print

        @ tac
        mov r0, $0xFF00
        orr r0, $0x0006
        bl mmu_rh
        bl hex_print

        /* Copy in emsg (86 bytes) */
        ldr r0, =emsg
        ldmia r0!, {r1-r6}
        stmia r7!, {r1-r6}
        ldmia r0!, {r1-r6}
        stmia r7!, {r1-r6}
        ldmia r0!, {r1-r6}
        stmia r7!, {r1-r6}
        ldmia r0!, {r1-r5}
        stmia r7!, {r1-r5}
        ldrh r1, [r0]
        strh r1, [r7]
        add r7, $0x02

        /* Print whole string */
        mov r0, $1
        mov r1, sp
        mov r2, $256
        add r2, $17
        mov r7, $4
        svc $0

        add sp, $255
        add sp, $35

        ldmfd sp!, {r2-r8, pc}

hex_print:
        ldr r3, =hexch

        @ Leading space
        mov r2, $' '
        strb r2, [r7]

        @ First nibble
        mov r2, r0
        and r2, $0xF
        ldrb r2, [r3, r2]
        strb r2, [r7, $4]

        @ Second nibble
        mov r2, r0, lsr $4
        and r2, $0xF
        ldrb r2, [r3, r2]
        strb r2, [r7, $3]

        @ Third nibble
        mov r2, r0, lsr $8
        and r2, $0xF
        ldrb r2, [r3, r2]
        strb r2, [r7, $2]

        @ Fourth nibble
        mov r2, r0, lsr $12
        and r2, $0xF
        ldrb r2, [r3, r2]
        strb r2, [r7, $1]

        add r7, $5

        mov pc, lr

        .end
