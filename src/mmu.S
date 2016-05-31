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

        .equ inpt, (mem + 0xFF00)
        .equ timr, (mem + 0xFF04)
        .equ intf, (mem + 0xFF0F)
        .equ inte, (mem + 0xFFFF)

        .bss

mem:    .space 65536
input:  .space 1
        .align

readop: .space 16
writeop:.space 16

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

        .global mmu_init
mmu_init:
        stmfd sp!, {r2-r4}

        /* Set up the MMU read operation map */
        @ 0x0000 - 0x3FFF
        mov r0, $(ropBIOS - ropb)
        orr r0, $((ropMEM - ropb) << 8)
        orr r0, $((ropMEM - ropb) << 16)
        orr r0, $((ropMEM - ropb) << 24)

        @ 0x4000 - 0x7FFF
        mov r1, $(ropMEM - ropb)
        orr r1, r1, lsl $0x08
        orr r1, r1, lsl $0x10

        @ 0x8000 - 0xBFFF
        mov r2, r1

        @ 0xC000 - 0xFFFF
        mov r3, r1

        ldr r4, =readop
        stmea r4, {r0-r3}

        /* Set up the MMU write operation map */
        @ 0x0000 - 0x3FFF
        mov r0, $(wopNOP - wopb)
        orr r0, r0, lsl $0x08
        orr r0, r0, lsl $0x10

        @ 0x4000 - 0x7FFF
        mov r1, r0

        @ 0x8000 - 0xBFFF
        mov r2, $(wopMEM - wopb)
        orr r2, r2, lsl $0x08
        orr r2, r2, lsl $0x10

        @ 0xC000 - 0xFFFF
        mov r3, $(wopWRAME - wopb)
        orr r3, r3, lsl $0x10
        orr r3, $((wopWRAMO - wopb) << 8)
        orr r3, $((wopMISC - wopb) << 24)

        ldr r4, =writeop
        stmea r4, {r0-r3}

        ldmfd sp!, {r2-r4}
        mov pc, lr

        .global mmu_load
mmu_load:
        stmfd sp!, {r2, r7}

        /* Open the file */
        mov r1, $0
        mov r2, $0
        mov r7, $5
        svc $0
        cmp r0, $0
        blt mmu_load_end

        /* Read the program */
        ldr r1, =mem
        mov r2, $0x8000
        mov r7, $3
        svc $0

        cmp r0, $0
        movhi r0, $0

        /* Close the file */
        mov r7, $6
        svc $0

mmu_load_end:
        ldmfd sp!, {r2, r7}
        mov pc, lr

        .global mmu_ri
mmu_ri:
        lsr r0, zpc, $0x10
        b mmu_rb

        .global mmu_ri1
mmu_ri1:
        add r0, zpc, $0x00010000
        lsr r0, $0x10
        b mmu_rb

        .global mmu_ri2
mmu_ri2:
        add r0, zpc, $0x00020000
        lsr r0, $0x10
        b mmu_rb

        .global mmu_rih1
mmu_rih1:
        add r0, zpc, $0x00010000
        lsr r0, $0x10
        b mmu_rh

        .global mmu_rif
mmu_rif:
        ldr r0, =intf
        ldrb r0, [r0]
        mov pc, lr

        .global mmu_rt
mmu_rt:
        ldr r0, =timr
        ldr r0, [r0]
        mov pc, lr

        .global mmu_rh
mmu_rh:
        stmfd sp!, {r2, lr}
        add r2, r0, $0x00000001
        bl mmu_rb
        mov r1, r0
        bic r0, r2, $0x00FF0000
        mov r2, r1
        bl mmu_rb
        orr r0, r2, r0, lsl $0x08
        ldmfd sp!, {r2, pc}

        .global mmu_wh
mmu_wh:
        stmfd sp!, {r2, lr}
        add r2, r0, $0x00010000
        bl mmu_wb
        lsr r0, r2, $0x10
        and r2, $0x0000FF00
        orr r0, r2, lsl $0x08
        ror r0, $0x10
        bl mmu_wb
        ldmfd sp!, {r2, pc}

        .global mmu_wt
mmu_wt:
        ldr r1, =timr
        str r0, [r1]
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

        @ Update the register
        ldr r1, =inpt
        ldrb r0, [r1]
        b wopINPT

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

        /* MMU BASE OPERATION DISPATCH */

        .global mmu_rb
mmu_rb:
        ldr r1, =readop
        ldrb r1, [r1, r0, lsr $0x0C]
        add pc, r1
        nop
ropb:

        .global mmu_wb
mmu_wb:
        ldr r1, =writeop
        ldrb r1, [r1, r0, lsr $0x1C]
        add pc, r1
        nop
wopb:

        /* MMU OPERATIONS */

        /*!
         * \brief Always read zero
         */
ropNOP:
        mov r0, $0x00
        mov pc, lr

        /*!
         * \brief Do nothing
         */
wopNOP:
        mov pc, lr

        /*!
         * \brief Read from BIOS if less than 256, otherwise from ROM
         *
         * During initialization, this routine is used to read BIOS instructions
         * from the special BIOS area. After writing to 0xFF50, this routine is
         * replaced with ropMEM, and is never used again.
         */
ropBIOS:
        cmp r0, $0x0100
        ldrhs r1, =mem
        ldrlo r1, =bios
        ldrb r0, [r1, r0]
        mov pc, lr

        /*!
         * \brief Generic memory read
         *
         * Reads normal memory from the base offset
         */
ropMEM:
        ldr r1, =mem
        ldrb r0, [r1, r0]
        mov pc, lr

        /*!
         * \brief Generic memory write
         */
wopMEM:
        ldr r1, =mem
        strb r0, [r1, r0, lsr $0x10]
        mov pc, lr

        /*!
         * \brief Special write routines for working ram
         *
         * Since working ram (0xC000-0xDFFF) mirrors the first 7680 bytes in
         * in 0xE000-0xFD00, we need to mirror the write operations. This will
         * make the read operations more efficient.
         */
wopWRAME:
        ldr r1, =mem
        strb r0, [r1, r0, lsr $0x10]
        eor r0, $0x20000000
        strb r0, [r1, r0, lsr $0x10]
        mov pc, lr

wopWRAMO:
        ldr r1, =mem
        strb r0, [r1, r0, lsr $0x10]
        cmp r0, $0xDE000000
        movhs pc, lr
        orr r0, $0x20000000
        strb r0, [r1, r0, lsr $0x10]
        mov pc, lr

        /*!
         * \brief Special write routine for WRAM, I/O, int, etc.
         */
wopMISC:
        @ Check for WRAM mirror
        cmp r0, $0xFE000000
        blo wopWRAME

        and r1, r0, $0x0FF00000

        @ Check for OAM
        cmp r1, $0x0EA00000
        blo wopMEM

        @ Check for unusable FEA0-FEFF
        cmp r1, $0x0F000000
        blo wopNOP

        ands r1, r0, $0x00FF0000

        @ Check for INPT
        beq wopINPT

        @ Check for INTE
        cmp r1, $0x00FF0000
        bhs wopINTE

        @ Check for HRAM
        cmp r1, $0x00800000
        bhs wopMEM

        cmp r1, $0x00500000
        beq wopBSWP

        @ Fall back to simple write
        b wopMEM

        /*!
         * \brief Special write routine for the joy pad input register
         *
         * The value when reading this register depends on the last value
         * written to it, so we update it whenever it is written to.
         */
wopINPT:
        bic r0, $0xC0
        orr r0, $0x0F

        ldr r1, =input
        ldrb r1, [r1]

        tst r0, $0x20
        bicne r0, r1, lsr $0x04

        tst r0, $0x10
        andne r1, $0x0F
        bicne r0, r1

        ldr r1, =inpt
        strb r0, [r1]
        mov pc, lr

        /*!
         * \brief Special write routine for the BIOS swap register
         *
         * When the BIOS writes to this register, it becomes inaccessible
         * and the ROM is accessed in it's place.
         */
wopBSWP:
        lsl r1, r0, $0x10
        cmp r1, $0x00010000
        movne pc, lr

        mov r0, $(ropMEM - ropb)
        ldr r1, =readop
        strb r0, [r1]

        mov pc, lr

        /*!
         * \brief Special write routine for INTE
         *
         * The interrupt enable bits are mirrored in the zil register for easy
         * access since they are read almost every single cycle.
         */
wopINTE:
        and r1, r0, $intM
        bic zil, $(intM << intO)
        orr zil, r1, lsl $intO
        ldr r1, =inte
        strb r0, [r1]
        mov pc, lr

        .end
