/******************************************************************************
 * \file dispatch.S
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
 * \brief Single-call dispatcher for calling into cpu.S, gpu.S and timer.S
 *
 * \author Scott K Logan
 ******************************************************************************/

        .include "reg.S"

        .bss

Z80RS:  .space 48
Z80RS_E:
SYSRS:  .space 40
SYSRS_E:

        .text

ZILINIT:.word 0x023C8000

        .global dispatch_enter
dispatch_enter:
        ldr r1, =SYSRS
        stmea r1, {r4-r13}

        ldr r1, =Z80RS_E
        ldmea r1, {r2-r13}

        mov pc, lr

        .global dispatch_leave
dispatch_leave:
        ldr r1, =Z80RS
        stmea r1, {r2-r13}

        ldr r1, =SYSRS_E
        ldmea r1, {r4-r13}

        mov pc, lr

        .global dispatch_init
dispatch_init:
        mov zil, lr

        bl cpu_init
        bl mmu_init
        bl display_init
        bl input_init

        mov lr, zil

        ldr zil, =ZILINIT
        ldr zil, [zil]

        mov pc, lr

        .global dispatch_stat
dispatch_stat:
        mov r0, lr
        bl dispatch_leave
        stmfd sp!, {r0}
        ldr r0, =Z80RS
        bl stat_print
        ldmfd sp!, {r0}
        bl dispatch_enter
        mov pc, r0

        .global dispatch_step
        .global gpu_ret
        .global timer_ret
        .global input_ret
        .global cpu_ret
dispatch_step:
        /* Check GPU */
        tst zil, $0x8000
        bne gpu_step
gpu_ret:

        /* Check Timer */
        ands r0, zil, $0xF8
        beq timer_step
timer_ret:

        /* Check Input */
        b input_step
input_ret:

        /* Check CPU */
        ands r0, zil, $0x07
        beq cpu_step
cpu_ret:

        /* Increment! */
        add zil, $0xF7

        b dispatch_ret

/* SPECIAL ROUTINES */

        .global cpu_exception
cpu_exception:
        bl dispatch_leave

        ldr r0, =Z80RS
        bl stat_print
        bl stat_cpu_exception

        mov r0, $0x08
        b dispatch_exit

        .global cpu_exit
cpu_exit:
        b dispatch_exit

        .end
