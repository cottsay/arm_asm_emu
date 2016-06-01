/******************************************************************************
 * \file framebuffer.S
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
 * \brief Display routines for 32-bit framebuffers
 *
 * \author Scott K Logan
 ******************************************************************************/

        .bss

morton: .space 512
render: .space 40
display:.space 4
llen:   .space 4

        .text

fbdev:  .asciz "/dev/fb0"
        .align

palette:.word 0x00FFFFFF        /* White */
        .word 0x00C0C0C0        /* Light */
        .word 0x00606060        /* Dark */
        .word 0x00000000        /* Black */

        .global display_init
display_init:
        stmfd sp!, {r2-r12, lr}

        /* Populate the morton table */
        ldr r0, =morton
        mov r1, $0xAA
        orr r1, r1, lsl $0x08
        mov r2, $0x00
        mov r3, $0x00
display_init_morton:
        /* Populate in reverse bit pattern */
        mov r4, $0x00
        tst r3, $0x01
        orrne r4, $0x100
        tst r3, $0x02
        orrne r4, $0x80
        tst r3, $0x04
        orrne r4, $0x40
        tst r3, $0x08
        orrne r4, $0x20
        tst r3, $0x10
        orrne r4, $0x10
        tst r3, $0x20
        orrne r4, $0x08
        tst r3, $0x40
        orrne r4, $0x04
        tst r3, $0x80
        orrne r4, $0x02

        strh r2, [r0, r4]

        add r2, $0x01
        add r2, r1
        bic r2, r1

        add r3, $0x01
        cmp r3, $0x200
        blo display_init_morton

        /* Open the device */
        ldr r0, =fbdev
        mov r1, $0x02
        mov r2, $0x00
        mov r7, $0x05
        svc $0
        mov r4, r0

        /* Get the line length using ioctl */
        sub sp, $0x46

        mov r1, $0x4600
        add r1, $0x0002
        mov r2, sp
        mov r7, $0x36
        swi $0

        ldr r2, [sp, $44]
        ldr r0, =llen
        str r2, [r0]

        add sp, $0x46

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

        bl display_clear

        ldmfd sp!, {r2-r12, pc}

        .global display_renderline
display_renderline:
        stmfd sp!, {r1-r12, lr}

        mov r12, $0xFF00

        /* Load Y pos in r2 */
        orr r0, r12, $0x0042
        bl mmu_rb
        mov r2, r0

        /* Load X pos in r3 */
        orr r0, r12, $0x0043
        bl mmu_rb
        mov r3, r0

        /* Load line number in r4 */
        orr r0, r12, $0x0044
        bl mmu_rb
        mov r4, r0

        /* Load status in r6 */
        orr r0, r12, $0x0040
        bl mmu_rb
        mov r6, r0

        /* Put map base in r7 */
        tst r6, $0x08
        movne r7, $0x9C00
        moveq r7, $0x9800

        /* Put tile base in r8 */
        tst r6, $0x10
        movne r8, $0x8000
        moveq r8, $0x8800

        /* Correct map offset, put line within tile in r2 */
        add r2, r4
        and r2, $0xFF
        lsr r9, r2, $0x03
        add r7, r9, lsl $0x05
        and r2, $0x07
        lsl r2, $0x01

        /* Correct tile line */
        add r8, r2

        /* Put map X offset in r3, put column within tile in r4 */
        and r4, r3, $0x07
        lsl r4, $0x01
        lsr r3, $0x03

        /* BEGIN LOAD */

        /* Load the first map cell */
        add r0, r7, r3
        bl mmu_rb

        /* Load the corresponding tile */
        tst r6, $0x10
        eoreq r0, $0x80
        lsl r0, $0x04

        add r2, r0, r8

        /* Interleave the bits */
        ldr r9, =morton
        mov r0, r2
        bl mmu_rb
        lsl r0, $0x01
        ldrh r5, [r9, r0]

        add r0, r2, $0x01
        bl mmu_rb
        lsl r0, $0x01
        ldrh r0, [r9, r0]
        orr r0, r5, r0, lsl $0x01

        /* Discard unneeded bits of this cell, store running cells in r12 */
        lsr r12, r0, r4

        /* From now on, we will shift in the other direction */
        rsb r4, $0x10

        /* Load destination into r10 */
        ldr r10, =render

        /* Initial value is in r12. Now we do this 20 times */
        mov r11, $0x14
display_rendertile:
        /* Move to next tile (and wrap) */
        add r3, $0x01
        and r3, $0x1F

        /* Load the next map cell */
        add r0, r7, r3
        bl mmu_rb

        /* Load the corresponding tile */
        tst r6, $0x10
        eoreq r0, $0x80
        lsl r0, $0x04

        add r2, r0, r8

        /* Interleave the bits */
        mov r0, r2
        bl mmu_rb
        lsl r0, $0x01
        ldrh r5, [r9, r0]

        add r0, r2, $0x01
        bl mmu_rb
        lsl r0, $0x01
        ldrh r0, [r9, r0]
        orr r0, r5, r0, lsl $0x01

        /* OR-in this tile after the previous tile's last bit */
        orr r12, r0, lsl r4

        /* Store the rendered bits */
        strh r12, [r10]
        add r10, $0x02

        /* Shift out the stored bits */
        lsr r12, $0x10

        /* Repeat */
        subs r11, $0x01
        bne display_rendertile

        ldmfd sp!, {r1-r12, pc}

        .global display_putline
display_putline:
        stmfd sp!, {r1-r12, lr}

        /* Load palette in r10 */
        /* TODO: Should this be fetched during renderline? */
        mov r2, $0xFF00
        orr r0, r2, $0x0047
        bl mmu_rb
        mov r10, r0

        /* Get the line number */
        orr r0, r2, $0x0044
        bl mmu_rb

        ldr r1, =display
        ldr r1, [r1]
        ldr r2, =llen
        ldr r2, [r2]

        mul r0, r2
        add r0, r1
        ldr r1, =render
        ldr r2, =palette
        mov r3, $0x0A

        /* r0 is dest, r1 is source, r2 is palette, r3 is counter */
do_sixteen:
        mov r4, $0x04
        ldr r5, [r1]
        ror r5, $0x1F

        /* r4 is sub-counter, r5 is source value */
do_four:
        and r6, r5, $0x06
        lsr r6, r10, r6
        and r6, $0x03
        ldr r6, [r2, r6, lsl $0x02]
        ror r5, $0x02

        and r7, r5, $0x06
        lsr r7, r10, r7
        and r7, $0x03
        ldr r7, [r2, r7, lsl $0x02]
        ror r5, $0x02

        and r8, r5, $0x06
        lsr r8, r10, r8
        and r8, $0x03
        ldr r8, [r2, r8, lsl $0x02]
        ror r5, $0x02

        and r9, r5, $0x06
        lsr r9, r10, r9
        and r9, $0x03
        ldr r9, [r2, r9, lsl $0x02]
        ror r5, $0x02

        stmia r0!, {r6-r9}

        subs r4, $0x01
        bne do_four

        subs r3, $0x01
        addne r1, $0x04
        bne do_sixteen

        ldmfd sp!, {r1-r12, pc}

display_clear:
        ldr r0, =display
        ldr r0, [r0]
        mov r1, $0x00
        mov r2, $0x00
        mvn r3, $0xFF000000
        ldr r4, =llen
        ldr r4, [r4]

clear_pixel:
        str r3, [r0, r2, lsl $0x02]
        add r2, $0x01
        cmp r2, $0xA0
        blo clear_pixel

        add r0, r4
        mov r2, $0x00

        add r1, $0x01
        cmp r1, $0x90
        blo clear_pixel

        ldr r0, =render
        mov r1, $0x00
        mov r2, $0x00
        mov r3, $0x00

        stmea r0!, {r1-r3}
        stmea r0!, {r1-r3}
        stmea r0!, {r1-r3}
        str r1, [r0]

        mov pc, lr

        .end
