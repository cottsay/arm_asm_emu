/******************************************************************************
 * \file terminal.S
 *
 * \copyright
 * Copyright &copy; 2019, Scott K Logan
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
 * \brief Modified Z80 Serial I/O Emulation
 *
 * \author Scott K Logan
 ******************************************************************************/

        .include "reg.S"

        .bss

ttyfd:  .space 4
ttybuff:.space 4
reg_bu: .space 16
        .align

        .text

ttydev: .asciz "/dev/null"
        .align

        .global serial_init
serial_init:
        str r7, [sp, $-0x04]!

        /* Open the device */
        ldr r0, =ttydev
        mov r1, $0x02
        mov r2, $0x800
        mov r7, $0x05
        svc $0

        /* Save the fd */
        ldr r1, =ttyfd
        str r0, [r1]

        ldr r7, [sp], $0x04
        mov pc, lr

        .global serial_xfer
serial_xfer:
        /* TODO: External clock is not implemented */
        tst r0, $(1 << 8)
        moveq pc, lr

        ldr r1, =reg_bu
        stmea r1, {r0, r2, r7, lr}

        ldr r1, =ttybuff
        strb r0, [r1]

        /* Write the byte */
        ldr r0, =ttyfd
        ldr r0, [r0]
        mov r2, $0x01
        mov r7, $0x04
        svc $0

        /* Transfer complete - clear the bit */
        ldr r0, =reg_bu
        ldr r0, [r0]
        bic r0, $(1 << 15)

        /* TODO: Read data and store it in SC */
        orr r0, $0xFF

        orr r0, $(0xFF00 << 16)
        orr r0, $(0x0001 << 16)
        bl mmu_wh

        ldr r1, =reg_bu
        ldmfd r1, {r0, r2, r7, pc}
