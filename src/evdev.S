/******************************************************************************
 * \file evdev.S
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
 * \brief Event input from evdev on Linux
 *
 * \author Scott K Logan
 ******************************************************************************/

        .include "reg.S"

        .bss

devfd:  .space 4

        .text

devpath:.asciz "/dev/input/event0"

        .align

        .global input_init
input_init:
        stmfd sp!, {r1-r3, r7}

        /* Open the device */
        ldr r0, =devpath
        mov r1, $0x00
        mov r2, $0x800
        mov r7, $0x05
        svc $0

        /* Save the fd */
        mov r3, r0
        ldr r1, =devfd
        str r3, [r1]

        /* Get the flags */
        mov r1, $0x03
        mov r2, $0x00
        mov r7, $0x37
        svc $0

        /* Set the flags */
        orr r2, r0, $0x800
        mov r0, r3
        mov r1, $0x04
        svc $0

        ldmfd sp!, {r1-r3, r7}
        mov pc, lr

        .global input_step
input_step:
        stmfd sp!, {r1-r2, r7}
        sub sp, $0x10

        /* Try to read 16 bytes */
        ldr r0, =devfd
        ldr r0, [r0]
        mov r1, sp
        mov r2, $0x10
        mov r7, $0x03
        svc $0
        cmp r0, $0x10
        bne input_step_ret

        /* Check if this is a key event */
        ldrh r0, [r1, $0x08]
        cmp r0, $0x01
        bne input_step_ret

        /* Check if this is either press or release */
        ldr r2, [r1, $0x0C]
        cmp r2, $0x00
        cmpne r2, $0x01
        bne input_step_ret

        /* Check for known characters */
        ldrh r1, [r1, $0x0A]
        mov r0, $0x00

        cmp r1, $0x11   @ W (Up)
        moveq r0, $0x40

        cmp r1, $0x1e   @ A (Left)
        moveq r0, $0x20

        cmp r1, $0x1f   @ S (Down)
        moveq r0, $0x80

        cmp r1, $0x20   @ D (Right)
        moveq r0, $0x10

        cmp r0, $0x00
        beq input_step_ret

        cmp r2, $0x00
        lsleq r0, $0x08

        bl mmu_input_update

        movne r0, $intJ
        blne mmu_int

input_step_ret:
        add sp, $0x10
        ldmfd sp!, {r1-r2, r7}
        b input_ret

        .end
