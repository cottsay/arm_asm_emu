/******************************************************************************
 * \file cpu.S
 *
 * \brief Modified Z80 CPU Emulation
 *
 * \author Scott K Logan
 ******************************************************************************/
.data
mem:    .space 65536
bios:   .byte 0xC3, 0xED, 0x00
        .space 234
        .byte 0x31, 0xFE, 0xFF, 0x21, 0x4D, 0x01, 0x11, 0xD8
        .byte 0x00, 0x01, 0xB0, 0x01, 0xC5, 0xF1, 0x01, 0x13
        .byte 0x00, 0xE0, 0x50

z80hdr: .byte 0x5a, 0x38, 0x30, 0x41, 0x53, 0x4d, 0x1a, 0x0a
        .byte 0x00, 0x00, 0x00, 0x00
filhdr: .space 10
        .byte 0x00, 0x00

.equ rom0, (mem)
.equ rom1, (mem + 16384)
.equ gram, (mem + 32768)
.equ eram, (mem + 40960)
.equ wram, (mem + 49152)

.text

.global mmu_init
mmu_init:
        mov pc, lr

.global mmu_load
mmu_load:
        /* Open the file */
        mov r1, $0
        mov r2, $0
        mov r7, $5
        swi $0
        cmp r0, $0
        movlt pc, lr

        /* Read the header */
        mov r8, r0
        mov r7, $3
        ldr r1, =filhdr
        mov r2, $10
        swi $0
        cmp r0, $0
        blt mmu_load_close
        cmp r0, $10
        bne mmu_load_bad_hdr

        /* Verify the header */
        ldr r0, =z80hdr
        ldr r1, =filhdr
        ldr r2, [r0]
        ldr r3, [r1]
        cmp r2, r3
        bne mmu_load_bad_hdr
        ldr r2, [r0, $4]
        ldr r3, [r1, $4]
        cmp r2, r3
        bne mmu_load_bad_hdr
        ldr r2, [r0, $8]
        ldr r3, [r1, $8]
        cmp r2, r3
        bne mmu_load_bad_hdr

        /* Read the program */
        mov r0, r8
        ldr r1, =mem
        mov r2, $65536
        mov r7, $3
        swi $0

        cmp r0, $0
        movgt r0, $0
        b mmu_load_close

mmu_load_bad_hdr:
        movne r0, $22

mmu_load_close:
        /* Close the file */
        mov r7, $6
        swi $0
        mov pc, lr

.global mmu_ri
mmu_ri:
        ldr r1, =mem
        ldrb r1, [r1, r11]
        mov pc, lr

.global mmu_ri1
mmu_ri1:
        ldr r1, =mem
        add r1, $1
        ldrb r1, [r1, r11]
        mov pc, lr

.global mmu_ris1
mmu_ris1:
        ldr r1, =mem
        add r1, $1
        ldrsb r1, [r1, r11]
        mov pc, lr

.global mmu_ri2
mmu_ri2:
        ldr r1, =mem
        add r1, $2
        ldrb r1, [r1, r11]
        mov pc, lr

.global mmu_rih1
mmu_rih1:
        ldr r1, =mem
        add r1, $1
        ldrh r1, [r1, r11]
        mov pc, lr

.global mmu_rb
mmu_rb:
        ldr r1, =mem
        ldrb r1, [r1, r0]
        mov pc, lr

.global mmu_wb
mmu_wb:
        ldr r1, =mem
        strb r0, [r1, r0, lsr $16]
        mov pc, lr

.global mmu_rh
mmu_rh:
        ldr r1, =mem
        ldrh r1, [r1, r0]
        mov pc, lr

.global mmu_wh
mmu_wh:
        ldr r1, =mem
        strb r0, [r1, r0, lsr $16]
        add r1, $1
        lsr r0, $8
        strb r0, [r1, r0, lsr $8]
        mov pc, lr
