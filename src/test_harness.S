/******************************************************************************
 * \file test_harness.S
 *
 * \copyright
 * Copyright &copy; 2020, Scott K Logan
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
 * \brief Emulator test harness initialization and startup for Linux
 *
 * \author Scott K Logan
 ******************************************************************************/

        .bss

counter:.space 4
exp_crc:.space 4

        .text

usage:  .ascii "Usage: test_harness ROM NUM_CYCLES EXPECTED_CRC [BMP_PATH]\n"
usage_e:.align

        .global _start
        .global dispatch_ret
_start:
        /* Parse CLA */
        ldr r0, [sp]
        cmp r0, $4
        cmpne r0, $5
        bne print_usage

        /* Load the ROM */
        ldr r0, [sp, $8]
        bl mmu_load
        cmp r0, $0
        bne dispatch_exit

        /* Parse NUM_CYCLES */
        ldr r0, [sp, $12]
        bl parse_hex
        ldr r1, =counter
        str r0, [r1]

        /* Parse EXPECTED_CRC */
        ldr r0, [sp, $16]
        bl parse_hex
        ldr r1, =exp_crc
        str r0, [r1]

        bl crc32_init
        cmp r0, $0
        bne dispatch_exit

dispatch_run:
        bl dispatch_init
dispatch_ret:
        ldr r1, =counter
        ldr r0, [r1]
        subs r0, $0x01
        strne r0, [r1]
        bne dispatch_step

        bl screen_compute_crc32
        ldr r1, =exp_crc
        ldr r1, [r1]
        cmp r0, r1
        moveq r0, $0x00
        beq dispatch_exit

        ldr r0, [sp]
        cmp r0, $4
        ldrne r0, [sp, $20]
        blne screen_save

        mov r0, $0x01

        .global dispatch_exit
dispatch_exit:
        mov r7, $1
        svc $0

parse_hex:
        ldrb r1, [r0], $0x01
        cmp r1, $'0'
        ldreqb r1, [r0], $0x01
        cmpeq r1, $'x'
        bne print_usage

        mov r1, $0x00
parse_hex_next:
        ldrb r2, [r0], $0x01
        cmp r2, $0x00
        beq parse_hex_end
        lsl r1, $0x04

        sub r2, $'0'
        cmp r2, $('9' - '0')
        addgt r1, $0x0A
        subgt r2, $('A' - '0')
        cmpgt r2, $('F' - 'A')
        subgt r2, $('a' - 'A')
        cmpgt r2, $('f' - 'a')
        bgt print_usage
        cmp r2, $0x00
        blt print_usage

        add r1, r2
        b parse_hex_next

parse_hex_end:
        mov r0, r1
        mov pc, lr

print_usage:
        stmfd sp!, {r7}
        mov r0, $1
        ldr r1, =usage
        mov r2, $(usage_e - usage)
        mov r7, $4
        svc $0
        ldmfd sp!, {r7}

        mov r0, $2
        b dispatch_exit

        .end
