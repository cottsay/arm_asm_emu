/******************************************************************************
 * \file cpu.S
 *
 * \brief Modified Z80 CPU Emulation
 *
 * \author Scott K Logan
 ******************************************************************************/
.data
bios:	.byte 0xC3, 0xED, 0x00
	.space 234
	.byte 0x31, 0xFE, 0xFF, 0x21, 0x4D, 0x01, 0x11, 0xD8
	.byte 0x00, 0x01, 0xB0, 0x01, 0xC5, 0xF1, 0x01, 0x13
	.byte 0x00, 0xE0, 0x50
mem:    .byte 0x06, 0x88, 0x0E, 0x88, 0x78, 0x81, 0xFD, 0x00
        .space 65536

.equ rom0, (mem)
.equ rom1, (mem + 16384)
.equ gram, (mem + 32768)
.equ eram, (mem + 40960)
.equ wram, (mem + 49152)

.text

.global mmu_init
mmu_init:
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
