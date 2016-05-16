/******************************************************************************
 * \file start.S
 *
 * \brief Emulator initialization and startup for Linux
 *
 * \author Scott K Logan
 ******************************************************************************/

        .text

        .global _start
        .global dispatch_ret
_start:
        /* Look for CLA */
        ldr r0, [sp]
        cmp r0, $1
        ble dispatch_run
        ldr r0, [sp, $8]
        bl mmu_load
        cmp r0, $0
        bne dispatch_exit

dispatch_run:
        bl dispatch_enter
        bl dispatch_init
dispatch_ret:
        mov r0, $0x00000600
        stupidloop:
            subs r0, $0x01
            bne stupidloop
        @bl dispatch_stat

        b dispatch_step

        .global dispatch_exit
dispatch_exit:
        bl dispatch_leave
        mov r7, $1
        svc $0

        .end
