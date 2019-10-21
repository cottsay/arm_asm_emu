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
linesp0:.space 44
linebg: .space 40
linesp1:.space 44
linest: .space 4
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
        sub sp, $0x44

        mov r1, $0x4600
        add r1, $0x0002
        mov r2, sp
        mov r7, $0x36
        swi $0

        ldr r2, [sp, $0x2C]
        ldr r0, =llen
        str r2, [r0]

        add sp, $0x44

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

        .global display_rendersprites
display_rendersprites:
        stmfd sp!, {r1-r10, lr}

        /*
         * r0: Line
         * r1: SCY
         * r2: SCX
         * r3: LCDC
         * r4: Palettes
         */
        bl mmu_rg

        /* Check if sprites are enabled */
        tst r3, $0x02
        ldmeqfd sp!, {r1-r10, pc}

        /* Offset line by 16 */
        add r2, r0, $0x10

        /* Skip the BG palette */
        lsr r4, $0x08

        /* Start at tile 39 */
        mov r5, $0x28

        /* Load the morton table */
        ldr r8, =morton

        /* Main Tile Loop
         * r2: Line
         * r3: LCDC
         * r4: Palettes
         * r5: Current sprite ID
         * r8: Morton table
         */
display_render_sprite:
        subs r5, $0x01
        bmi display_render_sprite_done

        /* Load the attributes in r0 */
        mov r0, r5
        bl mmu_rgs

        /* Put line within sprite in r6 */
        and r6, r0, $0x00FF
        rsbs r6, r2
        bmi display_render_sprite
        tst r3, $0x04
        moveq r1, $0x08
        movne r1, $0x10
        cmp r6, r1
        bhs display_render_sprite

        /* Put X in r7 */
        and r7, r0, $0xFF00
        lsr r7, $0x08
        subs r7, $0x08
        bmi display_render_sprite
        cmp r7, $0xA8
        bhs display_render_sprite

        /* Flip Y (if necessary) */
        tst r0, $0x40000000
        rsbne r6, $0x08

        /* Load the appropriate line addr in r10 */
        tst r0, $0x80000000
        ldreq r10, =linesp0
        ldrne r10, =linesp1

        /* Flip X (if necessary) */
        tst r0, $0x20000000

        /* Load the tile */
        lsr r0, $0x10
        and r0, $0xFF
        lsl r0, $0x04
        add r0, r6, lsl $0x01
        bl mmu_rgt

        /* Interleave the bits */
        and r1, r0, $0xFF
        lsl r1, $0x01
        lsr r0, $0x08
        lsl r0, $0x01
        ldrh r0, [r8, r0]
        ldrh r1, [r8, r1]
        orr r0, r1, r0, lsl $0x01

        beq no_flip_x

        mov r1, r0, lsr $0x0E
        lsl r0, $0x12
        ror r1, $0x02
        orr r1, r0, lsr $0x1E
        lsl r0, $0x02
        ror r1, $0x02
        orr r1, r0, lsr $0x1E
        lsl r0, $0x02
        ror r1, $0x02
        orr r1, r0, lsr $0x1E
        lsl r0, $0x02
        ror r1, $0x02
        orr r1, r0, lsr $0x1E
        lsl r0, $0x02
        ror r1, $0x02
        orr r1, r0, lsr $0x1E
        lsl r0, $0x02
        ror r1, $0x02
        orr r1, r0, lsr $0x1E
        lsl r0, $0x02
        orr r1, r0, lsr $0x1E
        ror r0, r1, $0x14

no_flip_x:
        /* Put the 8-pixel-block (2 bytes) offset in r1 */
        lsr r1, r7, $0x03

        /* r7 becomes the pixel offset after the 8-pixel-block */
        and r7, $0x07
        lsl r7, $0x01

        /* Load the current sprite data into lr */
        ldr lr, [r10, r1, lsl $0x01]

        @ TODO: Resolve the palette

        /* Mask out the old data */
        ldr r9, =$0x5555
        and r9, r0
        orr r9, r9, lsl $0x01
        bic lr, r9, lsl r7

        ldr r9, =$0xAAAA
        and r9, r0
        orr r9, r9, lsr $0x01
        bic lr, r9, lsl r7

        /* OR-in the new tile */
        orr lr, r0, lsl r7

        /* Store the modified data back to the line */
        str lr, [r10, r1, lsl $0x01]

        b display_render_sprite
display_render_sprite_done:

        ldmfd sp!, {r1-r10, pc}

        .global display_renderbg
display_renderbg:
        stmfd sp!, {r1-r10, lr}

        /*
         * r0: Line
         * r1: SCY
         * r2: SCX
         * r3: LCDC
         * r4: Palettes
         */
        bl mmu_rg

        /* Check if BG is enabled */
        tst r3, $0x01
        ldmeqfd sp!, {r1-r10, pc}

        /* Fix SCY based on current line */
        add r1, r0
        and r1, $0xFF

        /* Save the line state (palettes and line number) */
        orr r4, r0, lsl $0x18
        ldr lr, =linest
        str r4, [lr]

        /* Put map base in r5 */
        tst r3, $0x08
        movne r5, $0x0400
        moveq r5, $0x0000

        /* Put tile base in r6 */
        tst r3, $0x10
        movne r6, $0x0000
        moveq r6, $0x0800

        /* Correct map and tile base from SCY */
        lsr r0, r1, $0x03
        add r5, r0, lsl $0x05
        and r1, $0x07
        add r6, r1, lsl $0x01

        /* Put map column in r7 */
        lsr r7, r2, $0x03

        /* Put tile column in r2 */
        and r2, $0x07
        lsl r2, $0x01

        /* Load morton table in r8 */
        ldr r8, =morton

        /* Load line address in r9 */
        ldr r9, =linebg

        /* Not including initial tile, repeat 20 times */
        mov r10, $0x14

        /* BG Line Render Loop
         * r2: Tile column offset
         * r3: LCDC
         * r4: Running tile
         * r5: Map base
         * r6: Tile base
         * r7: Map column
         * r8: Morton table
         * r9: Destination line address
         * r10: Loop counter
         */

        /* Load the first map cell */
        add r0, r5, r7
        bl mmu_rgm

        /* Load the corresponding tile */
        tst r3, $0x10
        eoreq r0, $0x80
        lsl r0, $0x04
        add r0, r6
        bl mmu_rgt

        /* Interleave the bits */
        and r1, r0, $0xFF
        lsl r1, $0x01
        lsr r0, $0x08
        lsl r0, $0x01
        ldrh r0, [r8, r0]
        ldrh r1, [r8, r1]
        orr r0, r1, r0, lsl $0x01

        /* Discard unneeded bits of this cell */
        lsr r4, r0, r2

        /* From now on, we will shift in the other direction */
        rsb r2, $0x10

display_renderbg_tile:
        /* Move to next tile (and wrap) */
        add r7, $0x01
        and r7, $0x1F

        /* Load the next map cell */
        add r0, r5, r7
        bl mmu_rgm

        /* Load the corresponding tile */
        tst r3, $0x10
        eoreq r0, $0x80
        lsl r0, $0x04
        add r0, r6
        bl mmu_rgt

        /* Interleave the bits */
        and r1, r0, $0xFF
        lsl r1, $0x01
        lsr r0, $0x08
        lsl r0, $0x01
        ldrh r0, [r8, r0]
        ldrh r1, [r8, r1]
        orr r0, r1, r0, lsl $0x01

        /* OR this tile after the previous tile's last bit */
        orr r4, r0, lsl r2

        /* Store the newly rendered tile */
        strh r4, [r9], $0x02
        lsr r4, $0x10

        /* Repeat */
        subs r10, $0x01
        bne display_renderbg_tile

        ldmfd sp!, {r1-r10, pc}

        .global display_putline
display_putline:
        stmfd sp!, {r1-r12, lr}

        /* Get line in r0, palettes in r4 */
        ldr r2, =linest
        ldr r2, [r2]
        lsr r0, r2, $0x18

        ldr r1, =display
        ldr r1, [r1]
        ldr r4, =llen
        ldr r4, [r4]

        mul r0, r4
        add r0, r1
        ldr r1, =palette
        ldr r4, =linesp0
        ldr r5, =linebg
        ldr r6, =linesp1
        mov r3, $0x28

        /*
         * r0: Destination in framebuffer
         * r1: 32-bit palette
         * r2: Remap palettes
         * r3: Loop counter
         * r4: Sprite 0 line source
         * r5: Background line source
         * r6: Sprite 1 line source
         */
display_put_sixteen:
        ldr r7, [r4], $0x04
        ldr r8, [r5], $0x04
        ldr r9, [r6], $0x04
        ror r8, $0x1F

        /*
         * r7: Sprite 0 value
         * r8: Background value
         * r9: Sprite 1 value
         */
display_put_four:
        ands r10, r7, $0x03
        andeq r10, r8, $0x06
        lsreq r10, r2, r10
        andeqs r10, $0x03
        andeq r10, r9, $0x03
        ldr r10, [r1, r10, lsl $0x02]
        ror r7, $0x02
        ror r8, $0x02
        ror r9, $0x02

        ands r11, r7, $0x03
        andeq r11, r8, $0x06
        lsreq r11, r2, r11
        andeqs r11, $0x03
        andeq r11, r9, $0x03
        ldr r11, [r1, r11, lsl $0x02]
        ror r7, $0x02
        ror r8, $0x02
        ror r9, $0x02

        ands r12, r7, $0x03
        andeq r12, r8, $0x06
        lsreq r12, r2, r12
        andeqs r12, $0x03
        andeq r12, r9, $0x03
        ldr r12, [r1, r12, lsl $0x02]
        ror r7, $0x02
        ror r8, $0x02
        ror r9, $0x02

        ands lr, r7, $0x03
        andeq lr, r8, $0x06
        lsreq lr, r2, lr
        andeqs lr, $0x03
        andeq lr, r9, $0x03
        ldr lr, [r1, lr, lsl $0x02]
        ror r7, $0x02
        ror r8, $0x02
        ror r9, $0x02

        stmia r0!, {r10-r12, lr}

        sub r3, $0x01
        tst r3, $0x03
        bne display_put_four

        cmp r3, $0x00
        bne display_put_sixteen

        bl lines_clear

        ldmfd sp!, {r1-r12, pc}

display_clear:
        ldr r0, =linest
        mov r1, $0xE4
        orr r1, r1, lsl $0x08
        orr r1, r1, lsl $0x08
        str r1, [r0]

        ldr r0, =display
        ldr r0, [r0]
        mov r1, $0x00
        mov r2, $0x00
        mvn r3, $0xFF000000
        ldr r4, =llen
        ldr r4, [r4]

pixel_clear:
        str r3, [r0, r2, lsl $0x02]
        add r2, $0x01
        cmp r2, $0xA0
        blo pixel_clear

        add r0, r4
        mov r2, $0x00

        add r1, $0x01
        cmp r1, $0x90
        blo pixel_clear

lines_clear:
        mov r1, $0x00
        mov r2, $0x00
        mov r3, $0x00

        ldr r0, =linesp0
        stmea r0!, {r1-r3}
        stmea r0!, {r1-r3}
        stmea r0!, {r1-r3}
        stmea r0!, {r1-r2}

        ldr r0, =linebg
        stmea r0!, {r1-r3}
        stmea r0!, {r1-r3}
        stmea r0!, {r1-r3}
        str r1, [r0]

        ldr r0, =linesp1
        stmea r0!, {r1-r3}
        stmea r0!, {r1-r3}
        stmea r0!, {r1-r3}
        stmea r0!, {r1-r2}

        mov pc, lr

        .end
