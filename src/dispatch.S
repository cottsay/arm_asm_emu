/******************************************************************************
 * \file dispatch.S
 *
 * \brief Single-call dispatcher for calling into cpu.S, gpu.S and timer.S
 *
 * \author Scott K Logan
 ******************************************************************************/

        .include "reg.S"

        .bss

Z80RS:  .space 48
Z80RS_E:
SYSRS:  .space 40
SYSRS_E:

        .text

ZILINIT:.word 0x023C8000

        .global dispatch_enter
dispatch_enter:
        ldr r1, =SYSRS
        stmea r1, {r4-r13}

        ldr r1, =Z80RS_E
        ldmea r1, {r2-r13}

        mov pc, lr

        .global dispatch_leave
dispatch_leave:
        ldr r1, =Z80RS
        stmea r1, {r2-r13}

        ldr r1, =SYSRS_E
        ldmea r1, {r4-r13}

        mov pc, lr

        .global dispatch_init
dispatch_init:
        mov zil, lr

        bl cpu_init
        bl mmu_init

        mov lr, zil

        ldr zil, =ZILINIT
        ldr zil, [zil]

        mov pc, lr

        .global dispatch_stat
dispatch_stat:
        mov r0, lr
        bl dispatch_leave
        stmfd sp!, {r0}
        ldr r0, =Z80RS
        bl stat_print
        ldmfd sp!, {r0}
        bl dispatch_enter
        mov pc, r0

        .global dispatch_step
        .global timer_ret
        .global gpu_ret
        .global cpu_ret
dispatch_step:
        /* Check GPU */
        tst zil, $0x8000
        bne gpu_step
gpu_ret:

        /* Check Timer */
        ands r0, zil, $0xF8
        beq timer_step
timer_ret:

        /* Check CPU */
        ands r0, zil, $0x07
        beq cpu_step
cpu_ret:

        /* Increment! */
        add zil, $0xF7

        b dispatch_ret

/* SPECIAL ROUTINES */

        .global cpu_exception
cpu_exception:
        bl dispatch_leave

        ldr r0, =Z80RS
        bl stat_print
        bl stat_cpu_exception

        mov r0, $0x08
        b dispatch_exit

        .global cpu_exit
cpu_exit:
        b dispatch_exit

        .end
