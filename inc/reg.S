/******************************************************************************
 * \file reg.S
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
 * \brief Register aliases, flag definitions, and interrupt definitions
 *
 * \author Scott K Logan
 ******************************************************************************/

zop     .req r4
zra     .req r5
zbc     .req r6
zde     .req r7
zrf     .req r8
zhl     .req r9
zsp     .req r10
zpc     .req r11
zil     .req r12

        .equ flM, 0xF0  @ Mask
        .equ flZ, 0x80  @ Zero
        .equ flN, 0x40  @ Negative
        .equ flH, 0x20  @ Half-Carry
        .equ flC, 0x10  @ Carry
        .equ flNH, (flN | flH)
        .equ flZNH, (flZ | flN | flH)
        .equ flNHC, (flN | flH | flC)

        .equ intM, 0x1F @ Mask
        .equ intV, 0x01 @ V-Blank
        .equ intL, 0x02 @ LCDC Status
        .equ intT, 0x04 @ Timer Overflow
        .equ intS, 0x08 @ Serial Transfer
        .equ intJ, 0x10 @ Joy Pad Falling Edge

        @ zil-related offsets
        .equ intE, 0x20
        .equ intO, 0x1A
