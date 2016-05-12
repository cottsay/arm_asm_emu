/******************************************************************************
 * \file reg.S
 *
 * \brief Register aliases and flag definitions
 *
 * \author Scott K Logan
 ******************************************************************************/

zop     .req r2
zra     .req r3
zrb     .req r4
zrc     .req r5
zrd     .req r6
zre     .req r7
zrf     .req r8
zrh     .req r9
zrl     .req r10
zpc     .req r11
zil     .req r12
zsp     .req sp

        .equ flZ, 0x80
        .equ flN, 0x40
        .equ flH, 0x20
        .equ flC, 0x10


