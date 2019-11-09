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

        .equ ram, (_ram - 0xE000)
        .equ mem, (_mem - 0x8000)
        .equ tset, (mem + 0x8000)
        .equ tmap, (mem + 0x9800)
        .equ oam, (mem + 0xFE00)

        .equ misc, (mem + 0xFF00)
        .equ inpt, (misc)
        .equ sb, (misc + 0x01)
        .equ sc, (misc + 0x02)
        .equ div, (misc + 0x04)
        .equ intf, (misc + 0x0F)
        .equ lcdc, (misc + 0x40)
        .equ inte, (misc + 0xFF)

        .equ ctyp, (rom + 0x0147)

        .bss

rom:    .space 0x200000
_ram:   .space 0x20000
_mem:   .space 0x8000

readop: .space 0x10
writeop:.space 0x10

ram_off:.space 0x04
rom_off:.space 0x04
input:  .space 0x01

        .align

        .text

miscdfl:.byte 0xCF, 0x00, 0x7E, 0xFF, 0x00, 0x00, 0x00, 0xF8
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xE1
        .byte 0x80, 0xBF, 0xF3, 0xFF, 0xBF, 0xFF, 0x3F, 0x00
        .byte 0xFF, 0xBF, 0x7F, 0xFF, 0x9F, 0xFF, 0xBF, 0xFF
        .byte 0xFF, 0x00, 0x00, 0xBF, 0x77, 0xF3, 0xF1, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
        .byte 0x00, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        .byte 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF

        .align

bios:   .ifdef EMBED_BIOS
        .incbin "bios.rom", 0x00, 0x100
        .align
        .else
        .byte 0xC3, 0xED, 0x00
        .space 0xEA
        .byte 0x31, 0xFE, 0xFF, 0x21, 0x4D, 0x01, 0x11, 0xD8
        .byte 0x00, 0x01, 0xB0, 0x01, 0xC5, 0xF1, 0x01, 0x13
        .byte 0x00, 0xE0, 0x50
        .endif

        .global mmu_init
mmu_init:
        stmfd sp!, {r2-r8, lr}

        /* Set up the MMU read operation map */
        @ 0x0000 - 0x3FFF
        mov r0, $((ropBIOS - ropb) >> 2)
        orr r0, $((ropROM - ropb) << 6)
        orr r0, $((ropROM - ropb) << 14)
        orr r0, $((ropROM - ropb) << 22)

        @ 0x4000 - 0x7FFF
        mov r1, $((ropROM - ropb) >> 2)
        orr r1, r1, lsl $0x08
        orr r1, r1, lsl $0x10

        @ 0x8000 - 0xBFFF
        mov r2, $((ropMEM - ropb) >> 2)
        orr r2, $((ropNOP - ropb) << 14)
        orr r2, r2, lsl $0x08

        @ 0xC000 - 0xFFFF
        mov r3, $((ropMEM - ropb) >> 2)
        orr r3, $((ropMEM - ropb) << 6)
        orr r3, $((ropMEM - ropb) << 14)
        orr r3, $((ropMISC - ropb) << 22)

        ldr r4, =readop
        stmea r4, {r0-r3}

        /* Set up the MMU write operation map */
        @ 0x0000 - 0x3FFF
        mov r0, $((wopNOP - wopb) >> 2)
        orr r0, r0, lsl $0x08
        orr r0, r0, lsl $0x10

        @ 0x4000 - 0x7FFF
        mov r1, r0

        @ 0x8000 - 0xBFFF
        mov r2, $((wopMEM - wopb) >> 2)
        orr r2, $((wopNOP - wopb) << 14)
        orr r2, r2, lsl $0x08

        @ 0xC000 - 0xFFFF
        mov r3, $((wopWRAME - wopb) >> 2)
        orr r3, $((wopWRAMO - wopb) << 6)
        orr r3, $((wopWRAME - wopb) << 14)
        orr r3, $((wopMISC - wopb) << 22)

        ldr r4, =writeop
        stmea r4, {r0-r3}

        ldr r0, =miscdfl
        ldr r1, =misc
        ldmia r0!, {r2-r8, lr}
        stmia r1!, {r2-r8, lr}
        ldmia r0!, {r2-r8, lr}
        stmia r1!, {r2-r8, lr}
        ldmia r0!, {r2-r8, lr}
        stmia r1!, {r2-r8, lr}
        ldmia r0!, {r2-r8, lr}
        stmia r1!, {r2-r8, lr}

        ldr r0, =ctyp
        ldrb r0, [r0]
        cmp r0, $0x01
        blo mmu_init_ctype_ret
        ldr lr, =mmu_init_ctype_ret

        @ CType 1: 0x01 - 0x03
        cmp r0, $0x03
        ble mmu_init_mbc1

        @ CType 3: 0x11 - 0x13
        cmp r0, $0x11
        rsbgts r1, r0, $0x13
        bge mmu_init_mbc3

        @ Unsupported cartridge type - fall back on type 0x01
        bl mmu_init_mbc1

mmu_init_ctype_ret:
        ldmfd sp!, {r2-r8, pc}

mmu_init_mbc1:
        @ Initialize to RAM bank 0
        mov r0, $0x00
        ldr r1, =ram_off
        str r0, [r1]

        @ 0x0000 - 0x1FFF
        mov r0, $((wopMBC1RAME - wopb) >> 2)
        orr r0, r0, lsl $0x08

        ldr r1, =writeop
        strh r0, [r1]

        @ Initialize to ROM bank 1
        mov r0, $0x00
        ldr r1, =rom_off
        str r0, [r1]

        @ 0x4000 - 0x7FFF
        mov r0, $((ropROMB - ropb) >> 2)
        orr r0, r0, lsl $0x08
        orr r0, r0, lsl $0x10

        ldr r1, =readop
        str r0, [r1, $0x04]

        @ 0x2000 - 0x5FFF
        mov r0, $((wopMBC1ROM - wopb) >> 2)
        orr r0, $((wopMBC1ROMu - wopb) << 14)
        orr r0, r0, lsl $0x08

        ldr r1, =writeop
        str r0, [r1, $0x02]

        @ 0x6000 - 0x7FFF
        mov r0, $((wopMBC1RRM - wopb) >> 2)
        orr r0, r0, lsl $0x08

        strh r0, [r1, $0x06]

        mov pc, lr

mmu_init_mbc3:
        stmfd sp!, {lr}

        @ Start with MBC1
        bl mmu_init_mbc1

        @ 0x2000 - 0x5FFF
        mov r0, $((wopMBC3ROM - wopb) >> 2)
        orr r0, $((wopMBC1RAM - wopb) << 14)
        orr r0, r0, lsl $0x08

        ldr r1, =writeop
        str r0, [r1, $0x02]

        @ 0x6000 - 0x7FFF
        mov r0, $((wopNOP - wopb) >> 2)
        orr r0, r0, lsl $0x08

        strh r0, [r1, $0x06]

        ldmfd sp!, {pc}

        .global mmu_load
mmu_load:
        stmfd sp!, {r2, r7-r8}

        /* Open the file */
        mov r1, $0
        mov r2, $0
        mov r7, $5
        svc $0
        cmp r0, $0
        blt mmu_load_end

        mov r8, r0

        /* Read the program */
        ldr r1, =rom
        mov r2, $0x200000
        mov r7, $3
        svc $0

        cmp r0, $0
        ble mmu_load_end

        /* Close the file */
        mov r0, r8
        mov r7, $6
        svc $0

mmu_load_end:
        ldmfd sp!, {r2, r7-r8}
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
        and r0, $intM
        mov pc, lr

        .global mmu_rt
mmu_rt:
        ldr r0, =div
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
        ldr r1, =div
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
        b wopINTF

        .global mmu_sint
mmu_sint:
        ldr r1, =intf
        ldrb r1, [r1]
        bic r0, r1, r0
        b wopINTF

        /*!
         * \brief Read LCDC for the GPU
         */
        .global mmu_rg
mmu_rg:
        ldr r0, =lcdc
        ldrb r0, [r0]
        mov pc, lr

        /*!
         * \brief Write STAT and LY for the GPU
         *
         * Leave LY in r0 for the GPU to use
         */
        .global mmu_wg
mmu_wg:
        /* Update LYC comparison */
        ldr r1, =lcdc
        ldrb r1, [r1, $0x05]
        cmp r1, r0, lsr $0x08
        orreq r0, $0x04
        bicne r0, $0x04

        ldr r1, =lcdc
        strb r0, [r1, $0x01]
        lsr r0, $0x08
        strb r0, [r1, $0x04]
        mov pc, lr

        /*!
         * \brief Read LCDC and palettes for GPU
         */
        .global mmu_rgr
mmu_rgr:
        ldr r2, =lcdc
        ldr r4, [r2, $0x07]
        bic r4, $(0xFF << 0x18)
        ldrb r2, [r2]
        mov pc, lr

        /*!
         * \brief Read SCY and SCX for GPU
         */
        .global mmu_rgb
mmu_rgb:
        ldr r10, =lcdc
        ldrb r9, [r10, $0x02]
        ldrb r10, [r10, $0x03]
        mov pc, lr

        /*!
         * \brief Read WY and WX for GPU
         */
        .global mmu_rgw
mmu_rgw:
        ldr r10, =lcdc
        ldrb r9, [r10, $0x0A]
        ldrb r10, [r10, $0x0B]
        mov pc, lr

        /*!
         * \brief Read GPU tile data from VRAM
         */
        .global mmu_rgt
mmu_rgt:
        ldr r1, =tset
        ldrh r0, [r1, r0]
        mov pc, lr

        /*!
         * \brief Read GPU tile maps from VRAM
         */
        .global mmu_rgm
mmu_rgm:
        ldr r1, =tmap
        ldrb r0, [r1, r0]
        mov pc, lr

        /*!
         * \brief Read GPU sprite objects from OAM
         *
         * Takes a sprite index (0-39) in r0.
         */
        .global mmu_rgs
mmu_rgs:
        ldr r1, =oam
        ldr r0, [r1, r0, lsl $0x02]
        mov pc, lr

        /* MMU READ OPERATIONS */

        .global mmu_rb
mmu_rb:
        ldr r1, =readop
        ldrb r1, [r1, r0, lsr $0x0C]
        add pc, r1, lsl $0x02
        nop
ropb:

        /*!
         * \brief Always read zero
         */
ropNOP:
        mov r0, $0x00
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
        ldrhs r1, =rom
        ldrlo r1, =bios
        ldrb r0, [r1, r0]
        mov pc, lr

       /*!
        * \brief Banked ROM read
        */
ropROMB:
        ldr r1, =rom_off
        ldr r1, [r1]
        add r0, r1

        /*!
         * \brief Generic ROM read
         */
ropROM:
        ldr r1, =rom
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
         * \brief Banked external RAM read
         */
ropERAMB:
        ldr r1, =ram_off
        ldr r1, [r1]
        add r0, r1

        /*!
         * \brief External RAM read
         */
ropERAM:
        ldr r1, =ram
        ldrb r0, [r1, r0]
        mov pc, lr

        /*!
         * \brief Register read for clock seconds
         */
ropCLOCKs:
        mov pc, lr

        /*!
         * \brief Register read for clock minutes
         */
ropCLOCKm:
        mov pc, lr

        /*!
         * \brief Register read for clock hours
         */
ropCLOCKh:
        mov pc, lr

        /*!
         * \brief Register read for clock days
         */
ropCLOCKd:
        mov pc, lr

        /*!
         * \brief Register read for other misc. clock state
         */
ropCLOCKo:
        mov pc, lr

        /*!
         * \brief Special read routine for WRAM, I/O, int, etc.
         */
ropMISC:
        cmp r0, $0xFF00
        blt ropMEM

        and r1, r0, $0x00FF

        cmp r1, $0x0011
        beq ropNR11

        cmp r1, $0x0013
        beq ropNR13

        cmp r1, $0x0014
        beq ropNR14

        cmp r1, $0x0041
        beq ropSTAT

        b ropMEM

ropNR11:
        ldr r1, =mem
        ldrb r0, [r1, r0]
        orr r0, $0x3F
        mov pc, lr

ropNR13:
        mov r0, $0xFF
        mov pc, lr

ropNR14:
        ldr r1, =mem
        ldrb r0, [r1, r0]
        orr r0, $0xBF
        mov pc, lr

ropSTAT:
        ldr r1, =mem
        ldrb r0, [r1, r0]
        orr r0, $0x80
        mov pc, lr

        /* MMU WRITE OPERATIONS */

        .global mmu_wb
mmu_wb:
        ldr r1, =writeop
        ldrb r1, [r1, r0, lsr $0x1C]
        add pc, r1, lsl $0x02
        nop
wopb:

        /*!
         * \brief ROM/RAM switch mode for MBC1
         */
wopMBC1RRM:
        tst r0, $0x01

        @ 0x4000 - 0x5FFF
        moveq r0, $((wopMBC1ROMu - wopb) >> 2)
        movne r0, $((wopMBC1RAM - wopb) >> 2)
        orr r0, r0, lsl $0x08

        ldr r1, =writeop
        strh r0, [r1, $0x04]

wopNOP:
        mov pc, lr

        /*!
         * \brief RAM bank switch for MBC1
         */
wopMBC1RAM:
        and r0, $0x03
        lsl r0, $0x0D

        ldr r1, =ram_off
        str r0, [r1]

        mov pc, lr

        /*!
         * \brief RAM enable switch for MBC1
         */
wopMBC1RAME:
        and r0, $0x0F
        cmp r0, $0x0A

        @ 0xA000 - 0xBFFF
        moveq r0, $((ropERAMB - ropb) >> 2)
        orreq r0, $((wopERAMB - wopb) << 14)
        movne r0, $((ropNOP - ropb) >> 2)
        orrne r0, $((wopNOP - wopb) << 14)

        orr r0, r0, lsl $0x08

        ldr r1, =readop
        strh r0, [r1, $0x0A]

        ror r0, $0x10

        strh r0, [r1, $(0x0A + (writeop - readop))]

        mov pc, lr

        /*!
         * \brief ROM bank switch for MBC1
         */
wopMBC1ROM:
        ands r0, $0x1F
        subne r0, $0x01

        ldr r1, =rom_off
        ldr r1, [r1]

        bic r1, $(0x1F << 0x0E)
        orr r0, r1, r0, lsl $0x0E

wopMCB1ROMr:
        ldr r1, =rom_off
        str r0, [r1]

        mov pc, lr

        /*!
         * \brief ROM bank switch for MBC1
         */
wopMBC1ROMu:
        and r0, $0x03

        ldr r1, =rom_off
        ldr r1, [r1]

        bic r1, $(0x03 << 0x13)
        orr r0, r1, r0, lsl $0x13

        b wopMCB1ROMr

        /*!
         * \brief RAM bank and RTC register switch for MBC3
         */
wopMBC3RAM:
        and r1, r0, $0xFF
        cmp r1, $0x04
        blo wopMBC1RAM

        mov r0, $0x00

        cmp r1, $0x08
        moveq r0, $((ropCLOCKs - ropb) >> 2)
        orreq r0, $((wopNOP - wopb) << 14)

        cmp r1, $0x09
        moveq r0, $((ropCLOCKm - ropb) >> 2)
        orreq r0, $((wopNOP - wopb) << 14)

        cmp r1, $0x0A
        moveq r0, $((ropCLOCKh - ropb) >> 2)
        orreq r0, $((wopNOP - wopb) << 14)

        cmp r1, $0x0B
        moveq r0, $((ropCLOCKd - ropb) >> 2)
        orreq r0, $((wopNOP - wopb) << 14)

        cmp r1, $0x0C
        moveq r0, $((ropCLOCKo - ropb) >> 2)
        orreq r0, $((wopNOP - wopb) << 14)

        orr r0, r0, lsl $0x08

        ldr r1, =readop
        strh r0, [r1, $0x0A]

        ror r0, $0x10

        strh r0, [r1, $(0x0A + (writeop - readop))]

        mov pc, lr

        /*!
         * \brief ROM bank switch for MBC3
         */
wopMBC3ROM:
        ands r0, $0x7F
        subne r0, $0x01

        lsl r0, $0x0E

        ldr r1, =rom_off
        str r0, [r1]

        mov pc, lr

        /*!
         * \brief Generic memory write
         */
wopMEM:
        ldr r1, =mem
        strb r0, [r1, r0, lsr $0x10]
        mov pc, lr

        /*!
         * \brief Banked external RAM read
         */
wopERAMB:
        ldr r1, =ram_off
        ldr r1, [r1]

        add r1, r0, lsr $0x10
        orr r1, r0, lsl $0x18
        ror r0, r1, $0x18

        ldr r1, =ram
        strb r0, [r1, r0, lsr $0x08]
        mov pc, lr

        /*!
         * \brief External RAM read
         */
wopERAM:
        ldr r1, =ram
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

wopWRAMM:
        eor r0, $0x20000000
        strb r0, [r1, r0, lsr $0x10]
        mov pc, lr

wopWRAMO:
        ldr r1, =mem
        strb r0, [r1, r0, lsr $0x10]
        cmp r0, $0xDE000000
        blo wopWRAMM
        mov pc, lr

        /*!
         * \brief Special write routine to latch the clock
         */
wopCLOCKl:
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

        cmp r1, $0x00460000
        beq wopOAMDMA

        cmp r1, $0x00450000
        beq wopLYC

        cmp r1, $0x00440000
        beq wopLY

        cmp r1, $0x00410000
        beq wopSTAT

        cmp r1, $0x00400000
        beq wopLCDC

        cmp r1, $0x00260000
        beq wopNR52

        @ Check for INTF
        cmp r1, $0x000F0000
        beq wopINTF

        @ Check for DIV
        cmp r1, $0x00040000
        beq wopDIV

        @ Check for SC
        cmp r1, $0x00020000
        beq wopSC

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

        moveq r0, $((ropROM - ropb) >> 2)
        ldreq r1, =readop
        streqb r0, [r1]

        mov pc, lr

wopOAMDMA:
        ldr r1, =misc
        strb r0, [r1, $0x46]

        stmfd sp!, {r2-r4, lr}
        and r0, $0xFF
        lsl r2, r0, $0x08
        mov r3, $0x9F
        ldr r4, =oam

wopOAMDMAb:
        add r0, r2, r3
        bl mmu_rb
        strb r0, [r4, r3]

        subs r3, $0x01
        bpl wopOAMDMAb

        ldmfd sp!, {r2-r4, pc}

wopLYC:
        ldr r1, =lcdc
        strb r0, [r1, $0x05]

        and r0, $0xFF
        lsr r1, zil, $0x0F
        and r1, $0xFF
        cmp r0, r1

        ldr r1, =lcdc
        ldrb r0, [r1, $0x01]
        bicne r0, $0x04
        orreq r0, $0x04
        strb r0, [r1, $0x01]

        mov pc, lr

wopLY:
        mov r0, $0x00
        ldr r1, =lcdc
        strb r0, [r1, $0x04]

        bic zil, $(0x0F << 0x0F)
        bic zil, $(0xF0 << 0x0F)

        mov pc, lr

wopSTAT:
        and r0, $0x78

        ldr r1, =lcdc
        ldrb r1, [r1, $0x01]
        and r1, $0x07
        orr r0, r1

        ldr r1, =lcdc
        strb r0, [r1, $0x01]

        mov pc, lr

wopLCDC:
        ldr r1, =lcdc
        ldrb r1, [r1]

        @ Start HBlank if enabling LCD
        tst r0, $0x80
        cmpne r1, $0x80
        bicmi zil, $0x7000
        bicmi zil, $0x0FE0
        orrmi zil, $0x4200
        orrmi zil, $0x0060

        @ Clear LY, Mode if disabling LCD
        tst r0, $0x80
        biceq zil, $0x007F0000
        biceq zil, $0x0000F000
        orreq zil, $0x00000FE0

        ldr r1, =lcdc
        strb r0, [r1]

        @ Update STAT and LY for good measure
        lsr r0, zil, $0x07
        and r0, $(0xFF << 0x08)
        and r1, zil, $0x6000
        orr r0, r1, lsr $0x0D
        b mmu_wg

wopNR52:
        tst r0, $0x80

        ldr r1, =misc
        ldrb r0, [r1, $0x26]

        biceq r0, $0x80
        orrne r0, $0x80
        strb r0, [r1, $0x26]

        mov pc, lr

        /*!
         * \brief Special write routine for INTF
         *
         * The upper 3 bits of this register are always set.
         */
wopINTF:
        orr r0, $0xE0

        ldr r1, =misc
        strb r0, [r1, $0x0F] @ intf
        ldrb r1, [r1, $0xFF] @ inte

        and r1, r0
        and r1, $intM

        bic zil, $(intM << intO)
        orr zil, r1, lsl $intO
        mov pc, lr

        /*!
         * \brief Special write routine for DIV
         *
         * DIV is reset to 0 on write whenever DIV is written
         * to, regardless of the value being written.
         *
         * TODO: Since DIV plays a part in the incrementing of
         *       TIMA, we may need to reset the timer bits in
         *       zil and the internal timer routine divider
         *       to properly mimic that behavior.
         */
wopDIV:
        ldr r1, =div
        mov r0, $0x00
        strb r0, [r1]

        b timer_reset_div

        /*!
         * \brief Special write routine for SC
         *
         * When bit 7 rises, a serial transfer is initiated.
         */
wopSC:
        @ Test for bit 7 rising
        ldr r1, =sc
        ldrb r1, [r1]
        mvn r1, r1
        and r1, r0
        tst r1, $(1 << 7)

        ldr r1, =sc
        strb r0, [r1]

        moveq pc, lr

        ldr r1, =sb
        ldrh r0, [r1]
        b serial_xfer

        /*!
         * \brief Special write routine for INTE
         *
         * The interrupt enable bits are mirrored in the zil register for easy
         * access since they are read almost every single cycle.
         */
wopINTE:
        ldr r1, =misc
        strb r0, [r1, $0xFF] @ inte
        ldrb r1, [r1, $0x0F] @ intf

        and r1, r0
        and r1, $intM

        bic zil, $(intM << intO)
        orr zil, r1, lsl $intO
        mov pc, lr

        .end
