/******************************************************************************
 * \file timer.S
 *
 * \brief Modified Z80 timer and divider
 *
 * \author Scott K Logan
 ******************************************************************************/

        .include "reg.S"

        .text

        .global timer_step
timer_step:
        add zil, $0x100
        b timer_ret

        .end
