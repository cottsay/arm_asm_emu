/******************************************************************************
 * \file gpu.S
 *
 * \copyright
 * Copyright &copy; 2019, Scott K Logan
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
 * \brief Graphics processing dispatch
 *
 * \author Scott K Logan
 ******************************************************************************/

        .include "reg.S"

        .text

ziltbl:                  /*    -- Normal Transitions --    */
        .word 0x0000BD80 /* HBlank -> OAM    (+20  cycles) */
        .word 0x000071C0 /* VBlank -> VBlank (+114 cycles) */
        .word 0x00001AA0 /* OAM    -> VRAM   (+43  cycles) */
        .word 0xFFFF99A0 /* VRAM   -> HBlank (+51  cycles) */
                         /*    -- Special Transitions --   */
        .word 0xFFFFD440 /* OAM    -> VBlank (+94  cycles) */
        .word 0xFFB32BC0 /* VBlank -> OAM    (-94  cycles) */

        .global gpu_step
gpu_step:
        /* TODO: Optimize the GPU 'sleep' mode */
        bl mmu_rg
        tst r0, $0x80
        biceq zil, $0x1FC0
        beq gpu_ret

        /* Get the GPU mode alone (shifted left by 13) */
        ands r0, zil, $0x6000

        /* Display rendered line if ending HBlank */
        beq display_putline

        /* Look for sprites if ending OAM */
        cmp r0, $(0x02 << 0x0D)
        beq display_scan

        /* Render background line if ending VRAM */
        cmp r0, $(0x03 << 0x0D)
        beq display_render

        .global gpu_mode_ret
gpu_mode_ret:
        /* Get the GPU mode alone (shifted left by 13) */
        and r0, zil, $0x6000

        /* Add the corresponding transition value from ziltbl */
        ldr r1, =ziltbl
        ldr r0, [r1, r0, lsr $0x0B]
        add zil, r0

        /* Get the line number alone (shifted left by 8) */
        lsr lr, zil, $0x07
        and lr, $(0xFF << 0x08)

        /* On line 144, special transition to VBlank */
        cmp lr, $(0x90 << 0x08)
        ldreq r0, [r1, $0x10]
        addeq zil, r0

        /* On line 154, special transition from VBlank */
        cmp lr, $(0x9A << 0x08)
        ldreq r0, [r1, $0x14]
        addeq zil, r0

        /* Update STAT and LY with zil */
        and r1, zil, $0x6000
        orr r0, lr, r1, lsr $0x0D
        bl mmu_wg

        /* Trigger interrupt on VBlank */
        cmp r0, $0x90
        moveq r0, $intV
        bleq mmu_int

        b gpu_ret

        .end
