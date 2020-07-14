/******************************************************************************
 * \file bitmap_format.S
 *
 * \copyright
 * Copyright &copy; 2020, Scott K Logan
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
 * \brief Bitmap header offsets
 *
 * \author Scott K Logan
 ******************************************************************************/

        .equ bmp_header_file_size, 0x02
        .equ bmp_header_data_offset, 0x0A
        .equ bmp_header_bpp, 0x1C
        .equ bmp_header_data_size, 0x22
        .equ bmp_header_pallete_count, 0x2E

        .equ bmp_file_header_size, 0x0E
        .equ bmp_dib_header_size, 0x28
        .equ bmp_header_size, (bmp_file_header_size + bmp_dib_header_size)

        .macro bmp_header bpp, pallete_count
        /* BMP Header */
        .ascii "BM"
        .word  (bmp_header_size + (4 * \pallete_count) + (0xA0 * 0x90 * \bpp / 0x08)) @ File Size
        .hword 0x0000 @ Unused
        .hword 0x0000 @ Unused
        .word  bmp_header_size + (4 * \pallete_count) @ Data Offset
        /* DIB Header */
        .word  bmp_dib_header_size @ Size of this block
        .word  0x00A0 @ Width
        .word -0x0090 @ Height
        .hword 0x0001 @ Plane count
        .hword \bpp    @ BPP
        .word  0x0000 @ BI_RGB format
        .word  (0xA0 * 0x90 * \bpp / 0x08) @ Data Size
        .word  0x0CBC @ Horizontal DPI
        .word  0x0CBC @ Vertical DPI
        .word  \pallete_count @ Palette Color Count
        .word  0x0000 @ Important Color Count
        .endm
