/******************************************************************************
 * \file timer.S
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
 * \brief Modified Z80 timer and divider
 *
 * \author Scott K Logan
 ******************************************************************************/

        .include "reg.S"

        .bss

tadd:   .space 4

        .text

        .global timer_init
timer_init:
        mov r0, $0x00
        ldr r1, =tadd
        str r0, [r1]

        mov pc, lr

        .global timer_step
timer_step:
        ldr r0, =tadd
        ldr r1, [r0]
        add r1, $0x01
        str r1, [r0]

        bl mmu_rt

        /* Divider */
        tst r1, $0x0F
        roreq r0, $0x08
        addeq r0, $0x01000000
        roreq r0, $0x18
        bleq mmu_wt

        /* Timer */
        tst r0, $0x04000000
        beq timer_step_stopped

        /* Account for the control speed */
        lsl r1, $0x1A
        cmp r0, $0x05000000
        lsrhs r1, $0x1A
        cmp r0, $0x06000000
        rorhs r1, $0x02
        cmp r0, $0x07000000
        rorhs r1, $0x02
        lsrs r1, $0x1A

        /* Possibly increment the counter */
        roreq r0, $0x10
        addeq r0, $0x01000000
        roreq r0, $0x10

        /* If counter overflows, reset it to modulo */
        tsteq r0, $0xFF00
        andeq r1, r0, $0xFF0000
        orreq r0, r1, lsr $0x08

        bl mmu_wt

        /* Also trigger the timer interrupt */
        moveq r0, $intT
        bleq mmu_int

timer_step_stopped:
        add zil, $0x20
        b timer_ret

        .end
