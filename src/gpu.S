/******************************************************************************
 * \file gpu.S
 *
 * \brief Graphics processing routines
 *
 * \author Scott K Logan
 ******************************************************************************/

        .include "reg.S"

        .text

ziltbl:                  /*    -- Normal Transitions --    */
        .word 0x0005EC00 /* HBlank -> OAM    (+20  cycles) */
        .word 0x00038E00 /* VBlank -> VBlank (+114 cycles) */
        .word 0x0000D500 /* OAM    -> VRAM   (+43  cycles) */
        .word 0xFFFCCD00 /* VRAM   -> HBlank (+51  cycles) */
                         /*    -- Special Transitions --   */
        .word 0xFFFEA200 /* OAM    -> VBlank (+94  cycles) */
        .word 0xFD995E00 /* VBlank -> OAM    (-94  cycles) */

        .global gpu_step
gpu_step:
        /* Get the GPU mode alone */
        lsl lr, zil, $0x0E
        lsr lr, $0x1E

        /* Add the corresponding transition value from ziltbl */
        ldr r0, =ziltbl
        ldr lr, [r0, lr, lsl $0x02]
        add zil, lr

        /* Get the line number alone */
        lsl lr, zil, $0x06
        lsr lr, $0x18

        /* On line 144, special transition to VBlank */
        cmp lr, $0x90
        ldreq r0, [r0, $0x10]
        addeq zil, r0

        /* On line 154, special transition from VBlank */
        cmp lr, $0x9A
        ldreq r0, [r0, $0x14]
        addeq zil, r0

        b gpu_ret

        .end
