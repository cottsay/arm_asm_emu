	.text

	.global _start
_start:
	bl cpu_init
	bl mmu_init
	bl cpu_step
	mov r0, $0
	mov r7, $1
	swi $0
