/******************************************************************************
 * \file crc32.S
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
 * \brief 32-bit cyclic redundnancy check implementation
 *
 * \author Scott K Logan
 ******************************************************************************/

        .bss

lut:    .space (256 * 4)

        .text

        .global crc32_init
crc32_init:
        ldr r0, =lut
        ldr r1, =$0xEDB88320
        mov r2, $0x00

crc32_init_fill:
        lsr r3, r2, $0x18
        .rept 8
        lsrs r3, $0x01
        eorcs r3, r1
        .endr
        str r3, [r0, r2, lsr $0x16]
        adds r2, $(0x01 << 0x18)
        bne crc32_init_fill

        mov r0, $0x00
        mov pc, lr

        .global crc32_compute
crc32_compute:
        /* CRC32 calculation
         * r0: Data pointer
         * r1: Length
         * r2: Lookup Table
         * r3: Running CRC
         * r4: Scratch
         */

        cmp r1, $0x00
        moveq r0, $0x00
        moveq pc, lr

        stmfd sp!, {r4}

        ldr r2, =lut
        mov r3, $0xFFFFFFFF

crc32_compute_next:
        ldrb r4, [r0], $0x01
        eor r4, r3
        and r4, $0xFF
        ldr r4, [r2, r4, lsl $0x02]
        eor r3, r4, r3, lsr $0x08

        subs r1, $0x01
        bne crc32_compute_next

        ldmfd sp!, {r4}

        mvn r0, r3
        mov pc, lr

        .end
