/******************************************************************************
 * \file framebuffer.S
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
 * \brief 15-bit software framebuffer for rendering graphics
 *
 * \author Scott K Logan
 ******************************************************************************/

        .include "reg.S"

        .bss

        /* 8-bit -> 16-bit morton table for bit interleave */
morton: .space 0x200

        /* 160x2-bit frame line store */
line:   .space 0x28

        /* 10x32-bit prioritized sprite objects + 1 'zero' */
sprites:.space 0x2C

        .text

        .global display_init
display_init:
        stmfd sp!, {r2-r5}

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

        /* Ensure the first sprite is zero */
        mov r0, $0x00
        ldr r1, =sprites
        str r0, [r1]

        ldmfd sp!, {r2-r5}
        mov pc, lr

        .global display_scan
display_scan:
        stmfd sp!, {r2-r8}

        /* Get LCDC */
        bl mmu_rg

        /* Get LY and fix offset (16) */
        lsr r2, zil, $0x0F
        and r2, $0xFF
        add r2, $0x10

        /* Derive the minimum line based on LCDC and LY */
        tst r0, $0x04
        subeq r3, r2, $0x07
        subne r3, r2, $0x0F

        /* Start in OAM object 0 */
        mov r4, $0x00

        /* Start at the beginning of the object list */
        ldr r5, =sprites
        mov r6, $0x00

        /*
         * Main Sprite Search Loop
         * r0: Scratch
         * r1: Scratch
         * r2: Maximum line for sprite start
         * r3: Minimum line for sprite start
         * r4: Object index in OAM (0-39)
         * r5: Sprite object list address
         * r6: Next index in matching sprite object list (0-9)
         * r7: Scratch
         * r8: Scratch
         */
sprite_next:
        cmp r4, $0x28
        cmplo r6, $0x0A
        bhs sprite_scan_done

        mov r0, r4
        add r4, $0x01
        bl mmu_rgs

        /* Check Y */
        and r1, r0, $0x00FF
        cmp r1, r3
        cmpge r2, r1
        blt sprite_next

        mov r7, $0x00
sprite_sort_next:
        ldr r1, [r5, r7, lsl $0x02]
        and r8, r0, $0xFF00
        and lr, r1, $0xFF00

        cmp r8, lr
        cmplo r7, r6
        addlo r7, $0x01
        blo sprite_sort_next

sprite_bubble_next:
        str r0, [r5, r7, lsl $0x02]

        cmp r7, r6
        addlo r7, $0x01
        movlo r0, r1
        ldrlo r1, [r5, r7, lsl $0x02]
        blo sprite_bubble_next

        add r6, $0x01
        b sprite_next

sprite_scan_done:
        /* Fill the next with 0 */
        mov r0, $0x00
        str r0, [r5, r6, lsl $0x02]

        ldmfd sp!, {r2-r8}
        b gpu_mode_ret

        .global display_render
display_render:
        stmfd sp!, {r2-r11}

        bl mmu_rgr

        ldr r3, =line

        lsr r5, zil, $0x0F
        and r5, $0xFF

        ldr r6, =morton

        /*
         * r2: LCDC
         * r3: Frame Store Location
         * r4: Palettes
         * r5: Line
         * r6: Morton Table
         */

        /* Clear the line if the BG isn't enabled */
        tst r2, $0x01
        beq display_clear_no_bg

        /*
         * BG rendering section
         */

        bl mmu_rgb

        /* Fix SCY based on current line */
        add r9, r5
        and r9, $0xFF

        /* Put map base in r7 */
        tst r2, $0x08
        movne r7, $0x0400
        moveq r7, $0x0000

        /* Put tile base in r8 */
        tst r2, $0x10
        movne r8, $0x0000
        moveq r8, $0x0800

        /*
         * r7: Map Base
         * r8: Tile Base
         * r9: SCY
         * r10: SCX
         */

        /* Correct map and tile base from SCY */
        lsr r0, r9, $0x03
        add r7, r0, lsl $0x05
        and r9, $0x07
        add r8, r9, lsl $0x01

        /* Put map column in r9 */
        lsr r9, r10, $0x03

        /* Put tile column in r10 */
        and r10, $0x07
        lsl r10, $0x01

        /*
         * r9: Map Column
         * r10: Tile Column
         */

        /*
         * Main BG Render Routine
         */

        /* Load the first map cell */
        add r0, r7, r9
        bl mmu_rgm

        /* Load the corresponding tile */
        tst r2, $0x10
        eoreq r0, $0x80
        lsl r0, $0x04
        add r0, r8
        bl mmu_rgt

        /* Interleave the bits */
        and r1, r0, $0xFF
        lsl r1, $0x01
        lsr r0, $0x08
        lsl r0, $0x01
        ldrh r0, [r6, r0]
        ldrh r1, [r6, r1]
        orr r0, r1, r0, lsl $0x01

        /* Discard unneeded bits of this cell */
        lsr r11, r0, r10

        /* From now on, we will shift in the other direction */
        rsb r10, $0x10

        /* Abuse the unused upper bits of r4 for a loop counter */
        /* Repeat another 20 times */
        orr r4, $(0xEC << 0x18)

        /* BG Render Loop
         * r0: Scratch
         * r1: Scratch
         * r2: LCDC
         * r3: Frame Store Location
         * r4: Palettes / Loop Counter
         * r5: Line
         * r6: Morton Table
         * r7: Map Base
         * r8: Tile Base
         * r9: Map Column
         * r10: Tile Column
         * r11: Running Tile
         */
display_render_bg_tile:
         /* Move to next tile (and wrap) */
        add r9, $0x01
        and r9, $0x1F

        /* Load the next map cell */
        add r0, r7, r9
        bl mmu_rgm

        /* Load the corresponding tile */
        tst r2, $0x10
        eoreq r0, $0x80
        lsl r0, $0x04
        add r0, r8
        bl mmu_rgt

        /* Interleave the bits */
        and r1, r0, $0xFF
        lsl r1, $0x01
        lsr r0, $0x08
        lsl r0, $0x01
        ldrh r0, [r6, r0]
        ldrh r1, [r6, r1]
        orr r0, r1, r0, lsl $0x01

        /* OR this tile after the previous tile's last bit */
        orr r11, r0, lsl r10

        /* Resolve the palette for the next 8 pixels */
        ror r11, $0x1F

        and r0, r11, $0x06
        lsr r0, r4, r0
        mov r1, r0, lsl $0x1E
        lsr r1, $0x02
        ror r11, $0x01
        lsr r11, $0x01
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x02
        lsr r11, $0x02
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x02
        lsr r11, $0x02
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x02
        lsr r11, $0x02
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x02
        lsr r11, $0x02
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x02
        lsr r11, $0x02
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x02
        lsr r11, $0x02
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x10
        lsr r11, $0x03
        strh r1, [r3], $0x02

        /* Repeat */
        adds r4, $(0x01 << 0x18)
        bcc display_render_bg_tile

        ldr r3, =line

display_render_win:
        tst r2, $0x20
        beq display_render_sprites

        bl mmu_rgw

        /* Fix WY based on current line */
        rsbs r9, r5
        bmi display_render_sprites

        /* Fix the WX offset */
        subs r10, $0x07
        movmi r10, $0x00

        /* Put map base in r7 */
        tst r2, $0x40
        movne r7, $0x0400
        moveq r7, $0x0000

        /* Put tile base in r8 */
        tst r2, $0x10
        movne r8, $0x0000
        moveq r8, $0x0800

        /*
         * r7: Map Base
         * r8: Tile Base
         * r9: WY
         * r10: WX
         */

        /* Correct map and tile base from WY */
        lsr r0, r9, $0x03
        add r7, r0, lsl $0x05
        and r9, $0x07
        add r8, r9, lsl $0x01

        @TODO: We're ignoring WX entirely here

        /* Put map column in r9 */
        mov r9, $0x00

        /* Put tile column in r10 */
        mov r10, $0x00

        /*
         * r9: Map Column
         * r10: Tile Column
         */

        /*
         * Main WIN Render Routine
         */

        /* Load the first map cell */
        add r0, r7, r9
        bl mmu_rgm

        /* Load the corresponding tile */
        tst r2, $0x10
        eoreq r0, $0x80
        lsl r0, $0x04
        add r0, r8
        bl mmu_rgt

        /* Interleave the bits */
        and r1, r0, $0xFF
        lsl r1, $0x01
        lsr r0, $0x08
        lsl r0, $0x01
        ldrh r0, [r6, r0]
        ldrh r1, [r6, r1]
        orr r0, r1, r0, lsl $0x01

        /* Discard unneeded bits of this cell */
        lsr r11, r0, r10

        /* From now on, we will shift in the other direction */
        rsb r10, $0x10

        /* Abuse the unused upper bits of r4 for a loop counter */
        /* Repeat another 20 times */
        orr r4, $(0xEC << 0x18)

        /* WIN Render Loop
         * r0: Scratch
         * r1: Scratch
         * r2: LCDC
         * r3: Frame Store Location
         * r4: Palettes / Loop Counter
         * r5: Line
         * r6: Morton Table
         * r7: Map Base
         * r8: Tile Base
         * r9: Map Column
         * r10: Tile Column
         * r11: Running Tile
         */
display_render_win_tile:
         /* Move to next tile (and wrap) */
        add r9, $0x01
        and r9, $0x1F

        /* Load the next map cell */
        add r0, r7, r9
        bl mmu_rgm

        /* Load the corresponding tile */
        tst r2, $0x10
        eoreq r0, $0x80
        lsl r0, $0x04
        add r0, r8
        bl mmu_rgt

        /* Interleave the bits */
        and r1, r0, $0xFF
        lsl r1, $0x01
        lsr r0, $0x08
        lsl r0, $0x01
        ldrh r0, [r6, r0]
        ldrh r1, [r6, r1]
        orr r0, r1, r0, lsl $0x01

        /* OR this tile after the previous tile's last bit */
        orr r11, r0, lsl r10

        /* Resolve the palette for the next 8 pixels */
        ror r11, $0x1F

        and r0, r11, $0x06
        lsr r0, r4, r0
        mov r1, r0, lsl $0x1E
        lsr r1, $0x02
        ror r11, $0x01
        lsr r11, $0x01
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x02
        lsr r11, $0x02
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x02
        lsr r11, $0x02
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x02
        lsr r11, $0x02
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x02
        lsr r11, $0x02
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x02
        lsr r11, $0x02
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x02
        lsr r11, $0x02
        and r0, r11, $0x06
        lsr r0, r4, r0
        orr r1, r0, lsl $0x1E
        lsr r1, $0x10
        lsr r11, $0x03
        strh r1, [r3], $0x02

        /* Repeat */
        adds r4, $(0x01 << 0x18)
        bcc display_render_win_tile

        ldr r3, =line

display_render_sprites:
        tst r2, $0x02
        beq display_render_done

        /* Offset line by 16 */
        add r5, $0x10

        ldr r7, =sprites

        /* Ensure Palette index 0 is always transparent */
        bic r4, $(0x03 << 0x08)
        bic r4, $(0x03 << 0x10)

        /* Sprite Render Loop
         * r0: Scratch
         * r1: Scratch
         * r2: LCDC
         * r3: Frame Store Location
         * r4: Palettes / Loop Counter
         * r5: Line
         * r6: Morton Table
         * r7: Sprite List
         *
         * r8: Sprite Line
         * r9: Sprite X Offset
         * r10: Working Image Window
         * r11: Object Attributes
         */
display_render_sprite:
        ldr r11, [r7], $0x04
        cmp r11, $0x00
        beq display_render_done

        /* Put line within sprite in r8 */
        and r8, r11, $0x00FF
        rsb r8, r5

        /* Put X in r9 */
        and r9, r11, $0xFF00
        lsr r9, $0x08
        sub r9, $0x08

        /* Check X */
        cmp r9, $-0x08
        rsbgt r10, r9, $0xA0
        ble display_render_sprite

        /* Flip Y (if necessary) */
        tst r11, $0x40000000
        rsbne r8, $0x07
        tstne r2, $0x04
        addne r8, $0x08

        /* Load the tile */
        lsr r0, r11, $0x10
        and r0, $0xFF
        lsl r0, $0x04
        add r0, r8, lsl $0x01
        bl mmu_rgt

        /* Interleave the bits */
        and r1, r0, $0xFF
        lsl r1, $0x01
        lsr r0, $0x08
        lsl r0, $0x01
        ldrh r0, [r6, r0]
        ldrh r1, [r6, r1]
        orr r0, r1, r0, lsl $0x01

        tst r11, $0x20000000
        beq no_flip_x_sprite

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
        orr r1, r0, lsr $0x1C
        ror r0, r1, $0x14

no_flip_x_sprite:
        /* Calculate the mask */
        ldr r8, =$0x5555
        and r8, r0
        orr r8, r8, lsl $0x01

        ldr lr, =$0xAAAA
        and lr, r0
        orr lr, lr, lsr $0x01
        orr r8, lr

        /* Resolve the palette for the tile line */
        tst r11, $0x10000000
        roreq r10, r4, $0x08
        rorne r10, r4, $0x10

        lsl r0, $0x01

        and r1, r0, $0x06
        lsr r1, r10, r1
        mov lr, r1, lsl $0x1E
        lsr lr, $0x02
        lsr r0, $0x02
        and r1, r0, $0x06
        lsr r1, r10, r1
        orr lr, r1, lsl $0x1E
        lsr lr, $0x02
        lsr r0, $0x02
        and r1, r0, $0x06
        lsr r1, r10, r1
        orr lr, r1, lsl $0x1E
        lsr lr, $0x02
        lsr r0, $0x02
        and r1, r0, $0x06
        lsr r1, r10, r1
        orr lr, r1, lsl $0x1E
        lsr lr, $0x02
        lsr r0, $0x02
        and r1, r0, $0x06
        lsr r1, r10, r1
        orr lr, r1, lsl $0x1E
        lsr lr, $0x02
        lsr r0, $0x02
        and r1, r0, $0x06
        lsr r1, r10, r1
        orr lr, r1, lsl $0x1E
        lsr lr, $0x02
        lsr r0, $0x02
        and r1, r0, $0x06
        lsr r1, r10, r1
        orr lr, r1, lsl $0x1E
        lsr lr, $0x02
        lsr r0, $0x02
        and r1, r0, $0x06
        lsr r1, r10, r1
        orr lr, r1, lsl $0x1E
        lsr r0, lr, $0x10

        /* Put the 8-pixel-block (2 bytes) offset in r1 */
        asrs r1, r9, $0x03
        movmi r1, $0x00

        /* r9 becomes the pixel offset after the 8-pixel-block */
        lsl r9, $0x01
        andpl r9, $0x0F

        /* Handle pixel offset exceeding left of screen */
        negmi r9, r9
        lsrmi r8, r9
        lsrmi r0, r9
        movmi r9, $0x00

        /* Load the current image data into r10 */
        ldr r10, [r3, r1, lsl $0x01]

        tst r11, $0x80000000
        bne display_render_sprite_below

        /* Mask out the old data */
        bic r10, r8, lsl r9

        /* OR-in the new tile */
        orr r10, r0, lsl r9

        /* Store the modified data back to the line */
        str r10, [r3, r1, lsl $0x01]

        b display_render_sprite

display_render_sprite_below:
        /* Mask out the old data */
        ldr lr, =$0x5555
        and lr, r10, lr, lsl r9
        orr lr, lr, lsl $0x01
        bic r0, lr, lsr r9

        ldr lr, =$0xAAAA
        and lr, r10, lr, lsl r9
        orr lr, lr, lsr $0x01
        bic r0, lr, lsr r9

        /* OR-in the new tile */
        orr r10, r0, lsl r9

        /* Store the modified data back to the line */
        str r10, [r3, r1, lsl $0x01]

        b display_render_sprite

display_render_done:
        ldmfd sp!, {r2-r11}
        b gpu_mode_ret

        .global display_putline
display_putline:
        lsr r1, zil, $0x0F
        and r1, $0xFF

        ldr r0, =line

        b screen_putline_dmg

display_clear_no_bg:
        mov lr, r3
        mov r7, $0x00
        mov r8, $0x00
        mov r9, $0x00
        mov r10, $0x00
        mov r11, $0x00
        stmia lr!, {r7-r11}
        stmia lr!, {r7-r11}

        b display_render_win
