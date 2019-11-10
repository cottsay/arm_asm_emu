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

                         /*               |EIIIIIHS|BLLLLLLL|LMMMGGGG|GGGTTCCC|                             */
ziltbl:                  /*    -- Normal Transitions --     |        |  + -  -|                             */
        .word 0x00009020 /* HBlank -> OAM    (+1   cycles) 0|10010000|00100000| 000->001, inc L, G = (+1)   */
        .word 0x00003260 /* HBlank -> OAM    (+19  cycles) 0|00110010|01100000| 001->100,      , G = (+19)  */
        .word 0x00008E40 /* VBlank -> VBlank (+114 cycles) 0|10001110|01000000| 010->010, inc L, G = (+114) */
        .word 0x00001260 /* VBlank -> OAM    (+19  cycles) 0|00010010|01100000| 011->100,      , G = (+19)  */
        .word 0x00002560 /* OAM    -> VRAM   (+1   cycles) 0|00010000|00100000| 100->101,      , G = (+1)   */
        .word 0x00002560 /* OAM    -> VRAM   (+42  cycles) 0|00010101|01000000| 101->110,      , G = (+42)  */
        .word 0x00001020 /* VRAM   -> HBlank (+1   cycles) 0|00010000|00100000| 110->111,      , G = (+1)   */
        .word 0xFFFF9640 /* VRAM   -> HBlank (+50  cycles) 1|10100110|01000000| 111->000,      , G = (+50)  */
                         /*    -- Special Transitions --    |        |        |                             */
        .word 0xFFFFEBC0 /* OAM    -> VBlank (+94  cycles) 1|11101011|11000000| 100->010,      , G = (+94)  */
        .word 0xFFB301E0 /* VBlank -> OAM    (-113 cycles) *|00000001|11100000| 010->011, L-154, G = (-113) */

        .global gpu_step
gpu_step:
        /* TODO: Optimize the GPU 'sleep' mode */
        bl mmu_rg
        tst r0, $0x80
        orreq zil, $0x0FE0
        beq gpu_ret

        /* Get the GPU mode alone (shifted left by 12) */
        ands r0, zil, $0x7000

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
        /* Get the GPU mode alone (shifted left by 12) */
        and r0, zil, $0x7000

        /* Add the corresponding transition value from ziltbl */
        ldr r1, =ziltbl
        ldr r0, [r1, r0, lsr $0x0A]
        add zil, r0
        and r0, zil, $0x7000

        /* Get the line number alone (shifted left by 8) */
        lsr lr, zil, $0x07
        and lr, $(0xFF << 0x08)

        /* On line 144, special transition to VBlank */
        cmp lr, $(0x90 << 0x08)
        cmpeq r0, $0x4000
        ldreq r0, [r1, $0x20]
        addeq zil, r0

        /* On line 154, special transition from VBlank */
        cmp lr, $(0x9A << 0x08)
        ldreq r0, [r1, $0x24]
        addeq zil, r0
        bleq display_latch

        /* Update STAT and LY with zil */
        and r1, zil, $0x6000
        orr r0, lr, r1, lsr $0x0D
        bl mmu_wg

        /* Trigger interrupt on VBlank */
        and r1, zil, $0x7000
        cmp r0, $0x90
        cmpeq r1, $0x2000
        moveq r0, $intV
        bleq mmu_int

        b gpu_ret

        .end
