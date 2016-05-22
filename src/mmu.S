/******************************************************************************
 * \file mmu.S
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
 * \brief Modified Z80 MMU Emulation
 *
 * \author Scott K Logan
 ******************************************************************************/

        .include "reg.S"

        .equ rom0, (mem)
        .equ rom1, (mem + 16384)
        .equ gram, (mem + 32768)
        .equ eram, (mem + 40960)
        .equ wram, (mem + 49152)

        .equ intf, (mem + 0xFF0F)
        .equ inte, (mem + 0xFFFF)

        .bss

scr:    .space 32
scr_end:

bswp:   .space 256
mem:    .space 1
mem1:   .space 1
mem2:   .space 65536
bswpon: .space 2
input:  .space 1
        .align

        .text

bios:   .ifdef EMBED_BIOS
        .incbin "bios.rom", 0, 256
        .align
        .else
        .byte 0xC3, 0xED, 0x00
        .space 234
        .byte 0x31, 0xFE, 0xFF, 0x21, 0x4D, 0x01, 0x11, 0xD8
        .byte 0x00, 0x01, 0xB0, 0x01, 0xC5, 0xF1, 0x01, 0x13
        .byte 0x00, 0xE0, 0x50
        .endif

mmu_do_bswp:
        ldr r0, =scr
        stmea r0, {r2-r9}

        /* Copy bios swap to mem */
        ldr r0, =bswp
        ldr r1, =mem
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}

        /* RI overflow */
        sub r0, $0x0100
        add r1, $0xFF00
        ldrh r2, [r0]
        strh r2, [r1]

        ldr r0, =bswpon
        mov r1, $0x00
        strb r1, [r0]

        ldr r0, =input
        mov r1, $0x00
        strb r1, [r0]

        ldr r0, =scr_end
        ldmea r0, {r2-r9}

        mov pc, lr

        .global mmu_init
mmu_init:
        ldr r0, =scr
        stmea r0, {r2-r9}

        /* Copy bios to mem */
        ldr r0, =bios
        ldr r1, =mem
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}

        /* RI overflow */
        sub r0, $0x0100
        add r1, $0xFF00
        ldrh r2, [r0]
        strh r2, [r1]

        ldr r0, =bswpon
        mov r1, $0x01
        strb r1, [r0]

        ldr r0, =scr_end
        ldmea r0, {r2-r9}

        mov pc, lr

        .global mmu_load
mmu_load:
        stmfd sp!, {r4-r9}

        sub sp, $12

        /* Open the file */
        mov r1, $0
        mov r2, $0
        mov r7, $5
        svc $0
        cmp r0, $0
        blt mmu_load_end

        /* Read the program */
        ldr r1, =mem
        mov r2, $65536
        mov r7, $3
        svc $0

        cmp r0, $0
        ble mmu_load_close

        /* Copy data to bios swap */
        ldr r0, =mem
        ldr r1, =bswp
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}
        ldmia r0!, {r2-r9}
        stmia r1!, {r2-r9}

        mov r0, $0

mmu_load_close:
        /* Close the file */
        mov r7, $6
        svc $0

mmu_load_end:
        add sp, $12

        ldmfd sp!, {r4-r9}
        mov pc, lr

        .global mmu_ri
mmu_ri:
        ldr r0, =mem
        ldrb r0, [r0, zpc]
        mov pc, lr

        .global mmu_ri1
mmu_ri1:
        ldr r0, =mem1
        ldrb r0, [r0, zpc]
        mov pc, lr

        .global mmu_ri2
mmu_ri2:
        ldr r0, =mem2
        ldrb r0, [r0, zpc]
        mov pc, lr

        .global mmu_rih1
mmu_rih1:
        ldr r0, =mem1
        ldrh r0, [r0, zpc]
        mov pc, lr

        .global mmu_rif
mmu_rif:
        ldr r0, =intf
        ldrb r0, [r0]
        mov pc, lr

        .global mmu_rb
mmu_rb:
        ldr r1, =mem
        ldrb r0, [r1, r0]
        mov pc, lr

        .global mmu_rh
mmu_rh:
        ldr r1, =mem
        ldrh r0, [r1, r0]
        mov pc, lr

        .global mmu_wb
mmu_wb:
        ldr r1, =mem
        strb r0, [r1, r0, lsr $0x10]

        /* Check for special registers */
        cmp r0, $0xFF000000
        movlo pc, lr

        /* Check if writing to FF00 */
        tst r0, $0xFF0000
        beq mmu_input_compute

        /* Check if writing to FFFF */
        cmn r0, $0x10000
        andcs r0, $intM
        biccs zil, $(intM << intO)
        orrcs zil, r0, lsl $intO

        /* Check if writing 0x01 to 0xFF50 */
        eor r1, r0, $0xF500000
        eors r1, $0xF0000001
        movne pc, lr

        ldr r0, =bswpon
        ldrb r0, [r0]
        cmp r0, $0x00
        bne mmu_do_bswp
        mov pc, lr

        .global mmu_wh
mmu_wh:
        ldr r1, =mem
        add r1, r0, lsr $0x10
        strh r0, [r1]
        mov pc, lr

mmu_input_compute:
        ldr r1, =input
        ldrb r1, [r1]

        tst r0, $0x20
        orrne r0, r1, lsr $0x04

        tst r0, $0x10
        andne r1, $0x07
        orrne r0, r1

        ldr r1, =mem
        strb r0, [r1, r0, lsr $0x10]
        mov pc, lr

        .global mmu_input_update
mmu_input_update:
        ldr r1, =input
        ldrb r1, [r1]

        bic r1, r0, lsr $0x08

        and r0, $0xFF
        orr r1, r0

        ldr r0, =input
        strb r1, [r0]

        mov pc, lr

        .global mmu_int
mmu_int:
        ldr r1, =intf
        ldrb r1, [r1]
        orr r0, r1
        ldr r1, =intf
        strb r0, [r1]
        mov pc, lr

        .global mmu_sint
mmu_sint:
        ldr r1, =intf
        ldrb r1, [r1]
        bic r0, r1, r0
        ldr r1, =intf
        strb r0, [r1]
        mov pc, lr

        .end
