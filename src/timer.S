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
        .align

        .text

        .global timer_init
timer_init:
        mov r0, $0x00C00000
        ldr r1, =tadd
        str r0, [r1]

        mov pc, lr

        .global timer_reset_div
timer_reset_div:
        /* Clear bits 4+ if the divider */
        ldr r1, =tadd
        ldrh r0, [r1, $2]
        and r0, $0x000F
        strh r0, [r1, $2]

        /* Clear bits 2 and 3 (bits 0 and 1 are always clear) */
        bic zil, $0x18

        /* Anticipate an underflow on the next zil step */
        add zil, $0x20

        mov pc, lr

        /*
         * TODO: Handle a possible TIMA increment when timer enable
         *       goes low.
         */
        .global timer_step
timer_step:
        /* Anticipate an underflow on the next zil step */
        add zil, $0x20

        /* Get tadd */
        ldr r0, =tadd
        ldr r1, [r0]

        /* Check if overflow happened 1 cycle ago */
        /* TODO: This really needs to be optimized */
        tst r1, $0x0100
        bicne r1, $0x0100
        subne zil, $0x08
        strne r1, [r0]
        andne r0, r1, $0xFF
        orrne r0, $0xFF000000
        orrne r0, $0x00050000
        ldrne lr, =timer_ret
        bne mmu_wb

        /* Increment tadd */
        add r1, $0x00100000
        str r1, [r0]

        /* Get the timer state in r0 */
        bl mmu_rt

        /* Handle DIV */
        bic r0, $0xFF
        orr r0, r1, lsr $0x18

        /* Timer */
        ldr lr, =timer_ret
        tst r0, $0x04000000
        beq mmu_wt

        /* Account for the control speed */
        lsl r1, $0x06
        cmp r0, $0x05000000
        lsrhs r1, $0x1A
        cmp r0, $0x06000000
        rorhs r1, $0x02
        cmp r0, $0x07000000
        rorhs r1, $0x02

        lsrs r1, $0x1A
        bne mmu_wt

        /* Increment the counter */
        ror r0, $0x10
        adds r0, $0x01000000

        /* If counter overflows, save the modulo and set an event in 1 cycle */
        ldrcs r1, =tadd
        andcs lr, r0, $0xFF
        orrcs lr, $0x0100
        strcsh lr, [r1]
        subcs zil, $0x18
        ror r0, $0x10

        bl mmu_wt

        /* Return if no interrupt */
        bcc timer_ret

        /* Trigger the timer interrupt */
        ldr lr, =timer_ret
        mov r0, $intT
        b mmu_int

        .end
