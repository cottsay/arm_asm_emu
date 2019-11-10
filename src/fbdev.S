/******************************************************************************
 * \file fbdev.S
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
 * \brief Screen rendering routines for Linux framebuffer devices
 *
 * \author Scott K Logan
 ******************************************************************************/

        .bss

display:.space 4
llen:   .space 4

        .text

        /* DMG greyscale palette */
dmgpal: .hword 0xFFFF   /* White */
        .hword 0x6318   /* Light */
        .hword 0x318C   /* Dark */
        .hword 0x0000   /* Black */

fbdev:  .asciz "/dev/fb0"
        .align

        .global screen_init
screen_init:
        stmfd sp!, {r3-r5, r7}

        /* Open the device */
        ldr r0, =fbdev
        mov r1, $0x02
        mov r2, $0x00
        mov r7, $0x05
        svc $0
        movs r4, r0
        beq screen_init_end

        /* Get the line length using ioctl */
        sub sp, $0x44

        mov r1, $0x4600
        add r1, $0x0002
        mov r2, sp
        mov r7, $0x36
        swi $0

        ldr r2, [sp, $0x2C]
        add sp, $0x44

        cmp r0, $0x00
        bne screen_init_end
        cmp r2, $0x00
        beq screen_init_end

        ldr r0, =llen
        str r2, [r0]

        /* Map the display */
        mov r0, $0x00
        mov r1, $0x90
        mul r1, r2
        mov r2, $0x02
        mov r3, $0x01
        mov r5, $0x00
        mov r7, $0xC0
        svc $0

        ldr r1, =display
        str r0, [r1]

screen_init_end:
        ldmfd sp!, {r3-r5, r7}
        mov pc, lr

        /*
         * 40-byte line in r0
         * Line number in r1
         */
        .global screen_putline_dmg
screen_putline_dmg:
        ldr lr, =llen
        ldr lr, [lr]
        mul r1, lr

        ldr lr, =display
        ldr lr, [lr]
        cmp lr, $0x00
        beq gpu_mode_ret
        add r1, lr

        stmfd sp!, {r3-r12}

        ldr r3, =dmgpal

        mov r4, $0x0A

        /* DMG Palette Resolution Loop
         * r0: Source Line (2bpp)
         * r1: Target Line (16bpp)
         * r2: Scratch
         * r3: DMG Palette
         * r4: Loop Counter
         */

        /* Do the copy, 16 pixels at a time */
screen_put_16:
        ldr r2, [r0], $0x04

        ror r2, $0x1F
        and lr, r2, $0x06
        ldrh r5, [r3, lr]
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r6, [r3, lr]
        orr r5, r6, lsl $0x10
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r6, [r3, lr]
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r7, [r3, lr]
        orr r6, r7, lsl $0x10
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r7, [r3, lr]
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r8, [r3, lr]
        orr r7, r8, lsl $0x10
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r8, [r3, lr]
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r9, [r3, lr]
        orr r8, r9, lsl $0x10
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r9, [r3, lr]
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r10, [r3, lr]
        orr r9, r10, lsl $0x10
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r10, [r3, lr]
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r11, [r3, lr]
        orr r10, r11, lsl $0x10
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r11, [r3, lr]
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r12, [r3, lr]
        orr r11, r12, lsl $0x10
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh r12, [r3, lr]
        ror r2, $0x02
        and lr, r2, $0x06
        ldrh lr, [r3, lr]
        orr r12, lr, lsl $0x10

        stmia r1!, {r5-r12}

        subs r4, $0x01
        bne screen_put_16

        ldmfd sp!, {r3-r12}

        b gpu_mode_ret
