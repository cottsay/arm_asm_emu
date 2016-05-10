/******************************************************************************
 * \file mmu.S
 *
 * \brief Modified Z80 MMU Emulation
 *
 * \author Scott K Logan
 ******************************************************************************/

        .equ rom0, (mem)
        .equ rom1, (mem + 16384)
        .equ gram, (mem + 32768)
        .equ eram, (mem + 40960)
        .equ wram, (mem + 49152)

        .bss

bswap:  .space 256
mem:    .space 1
mem1:   .space 1
mem2:   .space 65534

        .text

bios:   .byte 0xC3, 0xED, 0x00
        .space 234
        .byte 0x31, 0xFE, 0xFF, 0x21, 0x4D, 0x01, 0x11, 0xD8
        .byte 0x00, 0x01, 0xB0, 0x01, 0xC5, 0xF1, 0x01, 0x13
        .byte 0x00, 0xE0, 0x50

        .global mmu_init
mmu_init:
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
        ldr r1, =bswap
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
        ldr r1, =mem
        ldrb r1, [r1, r11]
        mov pc, lr

        .global mmu_ri1
mmu_ri1:
        ldr r1, =mem1
        ldrb r1, [r1, r11]
        mov pc, lr

        .global mmu_ri2
mmu_ri2:
        ldr r1, =mem2
        ldrb r1, [r1, r11]
        mov pc, lr

        .global mmu_rih1
mmu_rih1:
        ldr r1, =mem1
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
        add r1, r0, lsr $0x10
        strh r0, [r1]
        mov pc, lr
