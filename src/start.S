/******************************************************************************
 * \file start.S
 *
 * \brief Emulator initialization and startup for Linux
 *
 * \author Scott K Logan
 ******************************************************************************/

        .text

        .global _start
_start:
        /* Look for CLA */
        ldr r0, [sp]
        cmp r0, $1
        ble _start_no_load
        ldr r0, [sp, $8]
        bl mmu_load
        cmp r0, $0
        bne _start_exit

_start_no_load:
        bl cpu_init
        bl mmu_init
        bl cpu_dispatch
_start_exit:
        mov r7, $1
        swi $0
