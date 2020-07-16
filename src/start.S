/******************************************************************************
 * \file start.S
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
 * \brief Emulator initialization and startup for Linux
 *
 * \author Scott K Logan
 ******************************************************************************/

        .bss

dbgflg: .space 4

        .text

sig1st: .word on_sigusr1
        .word 0x00
        .word 0x00
        .word 0x00
        .word 0x00

sig2st: .word on_sigusr2
        .word 0x00
        .word 0x00
        .word 0x00
        .word 0x00

        .global _start
        .global dispatch_ret
_start:
        /* Look for CLA */
        ldr r0, [sp]
        cmp r0, $1
        ble start_no_load
        ldr r0, [sp, $8]
        bl mmu_load
        cmp r0, $0
        bne dispatch_exit

start_no_load:
        mov r0, $0x00
        ldr r1, =dbgflg
        str r0, [r1]

        stmfd sp!, {r2, r7}

        /* Register for SIGUSR1 */
        mov r0, $0x0A
        ldr r1, =sig1st
        mov r2, $0x00
        mov r7, $0x43
        svc $0
        cmp r0, $0x00
        bne dispatch_exit

        /* Register for SIGUSR2 */
        mov r0, $0x0C
        ldr r1, =sig2st
        mov r2, $0x00
        mov r7, $0x43
        svc $0
        cmp r0, $0x00
        bne dispatch_exit

        ldmfd sp!, {r2, r7}

dispatch_run:
        bl dispatch_init
dispatch_ret:
        ldr r0, =dbgflg
        ldr r0, [r0]

        tst r0, $0x02
        moveq r1, $0x00000600
        movne r1, $0x00000001
        stupidloop:
            subs r1, $0x01
            bne stupidloop

        tst r0, $0x01
        blne dispatch_stat

        b dispatch_step

        .global dispatch_exit
dispatch_exit:
        mov r7, $1
        svc $0

on_sigusr1:
        ldr r1, =dbgflg
        ldr r0, [r1]
        eor r0, $0x01
        str r0, [r1]
        mov pc, lr

on_sigusr2:
        ldr r1, =dbgflg
        ldr r0, [r1]
        eor r0, $0x02
        str r0, [r1]
        mov pc, lr

        .end
