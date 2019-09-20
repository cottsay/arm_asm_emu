/******************************************************************************
 * \file gpu.S
 *
 * \copyright
 * Copyright &copy; 2016, Scott K Logan
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
        lsrs lr, $0x1E

        /* Display rendered line if ending HBlank */
        bleq display_putline

        /* Render sprite lines if ending OAM */
        cmp lr, $0x02
        bleq display_rendersprites

        /* Render background line if ending VRAM */
        cmp lr, $0x03
        bleq display_renderbg

        /* Get the GPU mode alone */
        lsl lr, zil, $0x0E
        lsrs lr, $0x1E

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

        /* Write line number to register */
        orr r0, lr, $0xFF000000
        orr r0, $0x00440000
        bl mmu_wb

        /* Write GPU mode to register */
        lsl r0, zil, $0x0E
        lsr r0, $0x1E
        orr r0, $0xFF000000
        orr r0, $0x00410000
        bl mmu_wb

        /* Trigger interrupt on VBlank */
        lsl lr, zil, $0x06
        lsr lr, $0x18
        cmp lr, $0x90
        moveq r0, $intV
        bleq mmu_int

        b gpu_ret

        .end
