/******************************************************************************
 * \file bitmap.S
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
 * \brief Screen rendering to a bitmap (.bmp) file
 *
 * \author Scott K Logan
 ******************************************************************************/

        .include "bitmap_format.S"

        .bss

        /* 160x144, 16bpp (RGB555), 2 buffers */
buffers:.space (160 * 144 * 2 * 2)

        /* Storage for color palette computation */
palette:.space (4 * 256)

        /* Storage for computation of indexed bitmap */
idxbuf: .space (160 * 144)

        /* Stores the currently active buffer */
active: .space 0x01

        .align

        .data

bmp_header_palletized:
        bmp_header 0x00, 0x00

        .align

        .text

        /* DMG greyscale palette (RGB555) */
dmgpal: .hword 0x7FFF   /* White */
        .hword 0x6318   /* Light */
        .hword 0x318C   /* Dark */
        .hword 0x0000   /* Black */

bmp_header_uncompressed_16bpp:
        bmp_header 0x10, 0x00

        .align

        .global screen_init
screen_init:
        mov pc, lr

        /*
         * 40-byte line in r0
         * Line number in r1
         */
        .global screen_putline_dmg
screen_putline_dmg:
        stmfd sp!, {r3-r12}

        cmp r1, $0x8F

        /* Offset buffer by line number */
        mov lr, $0x140
        mul r1, lr

        /* Flip the buffer for next time */
        ldr lr, =active
        ldrb r2, [lr]
        eorhs r3, r2, $0x01
        strhsb r3, [lr]

        /* Offset to back buffer */
        cmp r2, $0x00
        addne r1, $0xB400

        ldr lr, =buffers
        add r1, lr

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

        .global screen_compute_crc32
screen_compute_crc32:
        ldr r0, =buffers
        ldr r1, =active
        ldr r1, [r1]
        cmp r1, $0x00
        addeq r0, $0xB400
        mov r1, $(160 * 144 * 2)
        b crc32_compute

        .global screen_save
screen_save:
        stmfd sp!, {r3-r4, r7, lr}

        ldr r1, =palette
        mov r2, $0x00
        ldr r3, =buffers
        ldr lr, =active
        ldr lr, [lr]
        cmp lr, $0x00
        addeq r3, $0xB400

        /* Color-counting loop
         * r0: BMP save file path
         * r1: Color list pointer / Image max
         * r2: Color list size (x2)
         * r3: Image pointer
         * r4: Scratch
         * r7: Scratch
         * lr: Scratch
         */
count_colors:
        ldrh lr, [r3], $0x02

        mov r7, $0x00
color_locator:
        ldrh r4, [r1, r7]
        cmp r4, lr
        cmpne r7, r2
        addne r7, $0x02
        bne color_locator

        cmp r7, r2
        strhsh lr, [r1, r2]
        addhs r2, $0x02

        cmp r3, r1
        cmplo r2, $0x200
        blo count_colors

        sub r3, $0xB400

        /* BMP image type selection
         * r0: BMP save file path
         * r1: Color list pointer / Image max
         * r2: Color list size (x2)
         * r3: Image pointer
         * r4: Scratch
         * r7: Scratch
         * lr: Scratch
         */

        @ If color count <= 16, 4bpp palletized
        cmp r2, $0x20
        bls screen_save_4bpp

        @ If color count <= 256, 8bpp palletized
        cmp r2, $0x200
        bls screen_save_8bpp

        @ Else, uncompressed is most efficient

screen_save_uncompressed_16bpp:
        ldr r1, =$0x241
        mov r2, $0644
        mov r7, $0x05
        svc $0

        cmp r0, $0x00
        bmi screen_save_ret
        mov lr, r0

        ldr r1, =bmp_header_uncompressed_16bpp
        mov r2, $bmp_header_size
        mov r7, $0x04
        svc $0

        cmp r0, $0x00
        bmi screen_save_ret

        mov r0, lr
        ldr r1, =buffers
        ldr r2, =active
        ldr r2, [r2]
        cmp r2, $0x00
        addeq r1, $0xB400
        ldr r2, =bmp_header_uncompressed_16bpp
        ldr r2, [r2, $bmp_header_data_size]
        mov r7, $0x04
        svc $0

        cmp r0, $0x00
        bmi screen_save_ret

        mov r0, lr
        mov r7, $0x06
        svc $0

        mov r0, $0x00

        b screen_save_ret

screen_save_8bpp:
        /* 8bpp BMP image save
         * r0: BMP save file path
         * r1: Color list pointer / Image max
         * r2: Color list size (x2)
         * r3: Image pointer
         * r4: Scratch
         * r7: Scratch
         * lr: Scratch
         */

        @ Fill out the header
        ldr lr, =bmp_header_palletized
        ldr r7, =$0x5A36
        add r7, r2, lsl $0x01
        str r7, [lr, $bmp_header_file_size]

        mov r7, $0x36
        add r7, r2, lsl $0x01
        str r7, [lr, $bmp_header_data_offset]

        mov r7, $(0xA0 * 0x90)
        str r7, [lr, $bmp_header_data_size]

        mov r7, $0x08
        strh r7, [lr, $bmp_header_bpp]

        lsr r7, r2, $0x01
        str r7, [lr, $bmp_header_pallete_count]

        ldr r4, =idxbuf

        /* 8bpp image conversion
         * r0: BMP save file path
         * r1: Color list pointer
         * r2: Color list size (x2)
         * r3: Image pointer
         * r4: Palletized image pointer
         * r5: Scratch
         * r6: Scratch
         * r7: Loop Counter
         * lr: Scratch
         */

        stmfd sp!, {r5-r6}
        mov r7, $(160 * 144)
screen_convert_8bpp:
        ldrh r5, [r3], $0x02

        mov r6, $0x00
screen_convert_8bpp_find:
        ldrh lr, [r1, r6]
        cmp r5, lr
        addne r6, $0x02
        bne screen_convert_8bpp_find

        lsr r6, $0x01
        strb r6, [r4], $0x01

        subs r7, $0x01
        bne screen_convert_8bpp

        ldmfd sp!, {r5-r6}

        b screen_save_palletized

screen_save_4bpp:
        /* 4bpp BMP image save
         * r0: BMP save file path
         * r1: Color list pointer / Image max
         * r2: Color list size (x2)
         * r3: Image pointer
         * r4: Scratch
         * r7: Scratch
         * lr: Scratch
         */

        @ Fill out the header
        ldr lr, =bmp_header_palletized
        ldr r7, =$0x2D36
        add r7, r2, lsl $0x01
        str r7, [lr, $bmp_header_file_size]

        mov r7, $0x36
        add r7, r2, lsl $0x01
        str r7, [lr, $bmp_header_data_offset]

        mov r7, $(0xA0 * 0x90 / 0x02)
        str r7, [lr, $bmp_header_data_size]

        mov r7, $0x04
        strh r7, [lr, $bmp_header_bpp]

        lsr r7, r2, $0x01
        str r7, [lr, $bmp_header_pallete_count]

        ldr r4, =idxbuf

        /* 4bpp image conversion
         * r0: BMP save file path
         * r1: Color list pointer
         * r2: Color list size (x2)
         * r3: Image pointer
         * r4: Palletized image pointer
         * r5: Scratch
         * r6: Scratch
         * r7: Loop Counter
         * lr: Scratch
         */

        stmfd sp!, {r5-r6, r8}
        mov r7, $(160 * 144)
screen_convert_4bpp:
        ldrh r5, [r3], $0x02

        mov r6, $0x00
screen_convert_4bpp_find:
        ldrh lr, [r1, r6]
        cmp r5, lr
        addne r6, $0x02
        bne screen_convert_4bpp_find

        tst r7, $0x01
        lsleq r8, r6, $0x03
        orrne r8, r6, lsr $0x01
        strneb r8, [r4], $0x01

        subs r7, $0x01
        bne screen_convert_4bpp

        ldmfd sp!, {r5-r6, r8}

screen_save_palletized:
        /* 16bpp to 32bpp pallete conversion
         * r0: BMP save file path
         * r1: Color list pointer
         * r2: Color list size / Counter (x2)
         * r3: 16-bit color
         * r4: 24-bit color
         * r7: Scratch
         * lr: 527
         */

        sub r2, $0x02
        ldr lr, =$0x20F
pallete_convert:
        ldrh r3, [r1, r2]

        @ Ch1
        and r7, r3, $0x1F
        mul r7, lr
        add r7, $0x17
        lsr r4, r7, $0x06
        ror r4, $0x08

        @ Ch2
        and r7, r3, $(0x1F << 0x05)
        mul r7, lr
        add r7, $(0x17 << 0x05)
        orr r4, r7, lsr $0x0B
        ror r4, $0x08

        @ Ch3
        and r7, r3, $(0x1F << 0x0A)
        mul r7, lr
        add r7, $(0x17 << 0x0A)
        orr r4, r7, lsr $0x10
        ror r4, $0x10

        str r4, [r1, r2, lsl $0x01]

        subs r2, $0x02
        bpl pallete_convert

        @ Open the file

        ldr r1, =$0x241
        mov r2, $0644
        mov r7, $0x05
        svc $0

        cmp r0, $0x00
        bmi screen_save_ret
        mov lr, r0

        ldr r1, =bmp_header_palletized
        mov r2, $bmp_header_size
        mov r7, $0x04
        svc $0

        cmp r0, $0x00
        bmi screen_save_ret

        mov r0, lr
        ldr r1, =palette
        ldr r2, =bmp_header_palletized
        ldr r2, [r2, $bmp_header_pallete_count]
        lsl r2, $0x02
        mov r7, $0x04
        svc $0

        cmp r0, $0x00
        bmi screen_save_ret

        mov r0, lr
        ldr r1, =idxbuf
        ldr r2, =bmp_header_palletized
        ldr r2, [r2, $bmp_header_data_size]
        mov r7, $0x04
        svc $0

        cmp r0, $0x00
        bmi screen_save_ret

        mov r0, lr
        mov r7, $0x06
        svc $0

        mov r0, $0x00

screen_save_ret:
        ldmfd sp!, {r3-r4, r7, pc}

        .end
