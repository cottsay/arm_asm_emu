/******************************************************************************
 * \file cpu.S
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
 * \brief Modified Z80 CPU Emulation
 *
 * \author Scott K Logan
 *
 * The Modified Z80 CPU in the GBC contains 8 registers, a stack pointer and a
 * program counter. For as seamless as possible integration, actual ARM
 * registers will be used for much of the emulation (making it less-so emulation
 * and more so interpretation).
 *
 * Please note that internally, EABI calling conventions are not used.
 *
 * The layout of the system is as follows:
 * | Z80 Entity | ARM Entity |
 * | ---------- | ---------- |
 * | scratch    | r0         |
 * | scratch    | r1         |
 * | funcs      | r2         |
 * | ra         | r3         |
 * | rb         | r4         |
 * | rc         | r5         |
 * | rd         | r6         |
 * | re         | r7         |
 * | rf         | r8         |
 * | rhl        | r9         |
 * | sp         | r10        |
 * | pc         | r11        |
 * | il         | r12        |
 * |            | r13 (sp)   |
 * |            | r14 (lr)   |
 *
 * Since the individual opcode implementations use an absolute branch to return
 * to the CPU step routine, they sometimes use the ARM link register as a
 * scratch register. Many of them also invoke MMU routines, which writes to the
 * link register anyway.
 *
 * The zil (r12) reg is used to noop while instructions are "being executed" -
 * this ensures that the programs are run at the same rate as they were on the
 * Z80. Maybe we could decrease the clock by decresing this by a multiple...
 * I've yet to see it be anything but a multiple of 4, so maybe we can run the
 * Z80 clock at 1Mz and decrease this by counts of 4. Just a thought.
 *
 * The zop (r2) reg always contains the address of the operations table. This
 * allows us to branch without extra calls to memory using ldrls.
 ******************************************************************************/

        .include "reg.S"

        .bss
stash:  .space 8

        .text

ZOPS:   .word    opNOP,opLDBCnn, opLDBCA,  opIBC,   opIB,   opDB, opLDBn, opRLCA
        .word opLDnnSP, opAHLBC, opLDABC,  opDBC,   opIC,   opDC, opLDCn, opRRCA
        .word   opSTOP,opLDDEnn, opLDDEA,  opIDE,   opID,   opDD, opLDDn,  opRLA
        .word    opJRn, opAHLDE, opLDADE,  opDDE,   opIE,   opDE, opLDEn,  opRRA
        .word  opJRNZn,opLDHLnn,opLDHLiA,  opIHL,   opIH,   opDH, opLDHn,  opDAA
        .word   opJRZn, opAHLHL,opLDAHLi,  opDHL,   opIL,   opDL, opLDLn,  opCPL
        .word  opJRNCn,opLDSPnn,opLDHLdA,  opISP, opIHLm, opDHLm,opLDHLn,  opSCF
        .word   opJRCn, opAHLSP,opLDAHLd,  opDSP,   opIA,   opDA, opLDAn,  opCCF
        .word   opLDBB,  opLDBC,  opLDBD, opLDBE, opLDBH, opLDBL,opLDBHL, opLDBA
        .word   opLDCB,  opLDCC,  opLDCD, opLDCE, opLDCH, opLDCL,opLDCHL, opLDCA
        .word   opLDDB,  opLDDC,  opLDDD, opLDDE, opLDDH, opLDDL,opLDDHL, opLDDA
        .word   opLDEB,  opLDEC,  opLDED, opLDEE, opLDEH, opLDEL,opLDEHL, opLDEA
        .word   opLDHB,  opLDHC,  opLDHD, opLDHE, opLDHH, opLDHL,opLDHHL, opLDHA
        .word   opLDLB,  opLDLC,  opLDLD, opLDLE, opLDLH, opLDLL,opLDLHL, opLDLA
        .word  opLDHLB, opLDHLC, opLDHLD,opLDHLE,opLDHLH,opLDHLL, opHALT,opLDHLA
        .word   opLDAB,  opLDAC,  opLDAD, opLDAE, opLDAH, opLDAL,opLDAHL, opLDAA
        .word    opAAB,   opAAC,   opAAD,  opAAE,  opAAH,  opAAL, opAAHL,  opAAA
        .word   opAcAB,  opAcAC,  opAcAD, opAcAE, opAcAH, opAcAL,opAcAHL, opAcAA
        .word    opSAB,   opSAC,   opSAD,  opSAE,  opSAH,  opSAL, opSAHL,  opSAA
        .word   opScAB,  opScAC,  opScAD, opScAE, opScAH, opScAL,opScAHL, opScAA
        .word   opANAB,  opANAC,  opANAD, opANAE, opANAH, opANAL,opANAHL, opANAA
        .word   opXOAB,  opXOAC,  opXOAD, opXOAE, opXOAH, opXOAL,opXOAHL, opXOAA
        .word   opORAB,  opORAC,  opORAD, opORAE, opORAH, opORAL,opORAHL, opORAA
        .word    opCAB,   opCAC,   opCAD,  opCAE,  opCAH,  opCAL, opCAHL,  opCAA
        .word  opRETNZ, opPOPBC,opJPNZnn, opJPnn,opCNZnn,opPUSBC,  opAAn, opR00H
        .word   opRETZ,   opRET, opJPZnn,  opCBP, opCZnn,  opCnn, opAcAn, opR08H
        .word  opRETNC, opPOPDE,opJPNCnn,   opNI,opCNCnn,opPUSDE,  opSAn, opR10H
        .word   opRETC,  opRETI, opJPCnn,   opNI, opCCnn,   opNI, opScAn, opR18H
        .word  opLDFnA, opPOPHL, opLDFCA,   opNI,   opNI,opPUSHL, opANAn, opR20H
        .word   opASPn,  opJPHL, opLDnnA,   opNI,   opNI,   opNI, opXOAn, opR28H
        .word  opLDAFn, opPOPAF, opLDAFC,   opDI,   opNI,opPUSAF, opORAn, opR30H
        .word opLDHLSn, opLDSHL, opLDAnn,   opEI,   opNI, opEXIT,  opCAn, opR38H
        .word   cbRLCB,  cbRLCC,  cbRLCD, cbRLCE, cbRLCH, cbRLCL,cbRLCHL, cbRLCA
        .word   cbRRCB,  cbRRCC,  cbRRCD, cbRRCE, cbRRCH, cbRRCL,cbRRCHL, cbRRCA
        .word    cbRLB,   cbRLC,   cbRLD,  cbRLE,  cbRLH,  cbRLL, cbRLHL,  cbRLA
        .word    cbRRB,   cbRRC,   cbRRD,  cbRRE,  cbRRH,  cbRRL, cbRRHL,  cbRRA
        .word   cbSLAB,  cbSLAC,  cbSLAD, cbSLAE, cbSLAH, cbSLAL,cbSLAHL, cbSLAA
        .word   cbSRAB,  cbSRAC,  cbSRAD, cbSRAE, cbSRAH, cbSRAL,cbSRAHL, cbSRAA
        .word   cbSWPB,  cbSWPC,  cbSWPD, cbSWPE, cbSWPH, cbSWPL,cbSWPHL, cbSWPA
        .word   cbSRLB,  cbSRLC,  cbSRLD, cbSRLE, cbSRLH, cbSRLL,cbSRLHL, cbSRLA
        .word   cbBT0B,  cbBT0C,  cbBT0D, cbBT0E, cbBT0H, cbBT0L,cbBT0HL, cbBT0A
        .word   cbBT1B,  cbBT1C,  cbBT1D, cbBT1E, cbBT1H, cbBT1L,cbBT1HL, cbBT1A
        .word   cbBT2B,  cbBT2C,  cbBT2D, cbBT2E, cbBT2H, cbBT2L,cbBT2HL, cbBT2A
        .word   cbBT3B,  cbBT3C,  cbBT3D, cbBT3E, cbBT3H, cbBT3L,cbBT3HL, cbBT3A
        .word   cbBT4B,  cbBT4C,  cbBT4D, cbBT4E, cbBT4H, cbBT4L,cbBT4HL, cbBT4A
        .word   cbBT5B,  cbBT5C,  cbBT5D, cbBT5E, cbBT5H, cbBT5L,cbBT5HL, cbBT5A
        .word   cbBT6B,  cbBT6C,  cbBT6D, cbBT6E, cbBT6H, cbBT6L,cbBT6HL, cbBT6A
        .word   cbBT7B,  cbBT7C,  cbBT7D, cbBT7E, cbBT7H, cbBT7L,cbBT7HL, cbBT7A
        .word   cbRS0B,  cbRS0C,  cbRS0D, cbRS0E, cbRS0H, cbRS0L,cbRS0HL, cbRS0A
        .word   cbRS1B,  cbRS1C,  cbRS1D, cbRS1E, cbRS1H, cbRS1L,cbRS1HL, cbRS1A
        .word   cbRS2B,  cbRS2C,  cbRS2D, cbRS2E, cbRS2H, cbRS2L,cbRS2HL, cbRS2A
        .word   cbRS3B,  cbRS3C,  cbRS3D, cbRS3E, cbRS3H, cbRS3L,cbRS3HL, cbRS3A
        .word   cbRS4B,  cbRS4C,  cbRS4D, cbRS4E, cbRS4H, cbRS4L,cbRS4HL, cbRS4A
        .word   cbRS5B,  cbRS5C,  cbRS5D, cbRS5E, cbRS5H, cbRS5L,cbRS5HL, cbRS5A
        .word   cbRS6B,  cbRS6C,  cbRS6D, cbRS6E, cbRS6H, cbRS6L,cbRS6HL, cbRS6A
        .word   cbRS7B,  cbRS7C,  cbRS7D, cbRS7E, cbRS7H, cbRS7L,cbRS7HL, cbRS7A
        .word   cbST0B,  cbST0C,  cbST0D, cbST0E, cbST0H, cbST0L,cbST0HL, cbST0A
        .word   cbST1B,  cbST1C,  cbST1D, cbST1E, cbST1H, cbST1L,cbST1HL, cbST1A
        .word   cbST2B,  cbST2C,  cbST2D, cbST2E, cbST2H, cbST2L,cbST2HL, cbST2A
        .word   cbST3B,  cbST3C,  cbST3D, cbST3E, cbST3H, cbST3L,cbST3HL, cbST3A
        .word   cbST4B,  cbST4C,  cbST4D, cbST4E, cbST4H, cbST4L,cbST4HL, cbST4A
        .word   cbST5B,  cbST5C,  cbST5D, cbST5E, cbST5H, cbST5L,cbST5HL, cbST5A
        .word   cbST6B,  cbST6C,  cbST6D, cbST6E, cbST6H, cbST6L,cbST6HL, cbST6A
        .word   cbST7B,  cbST7C,  cbST7D, cbST7E, cbST7H, cbST7L,cbST7HL, cbST7A

        .global cpu_init
cpu_init:
        ldr zop, =ZOPS
        mov zpc, $0x00000000

        mov pc, lr

cpu_int:
        bic zil, $(intE << intO)        @ Disable interrupts

        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        /* Figure out which interrupt to service */
        tst zil, $(intV << intO)
        movne r0, $intV
        movne zpc, $0x00400000

        tst zil, $(intL << intO)
        movne r0, $intL
        movne zpc, $0x00480000

        tst zil, $(intT << intO)
        movne r0, $intT
        movne zpc, $0x00500000

        tst zil, $(intS << intO)
        movne r0, $intS
        movne zpc, $0x00580000

        tst zil, $(intJ << intO)
        movne r0, $intJ
        movne zpc, $0x00600000

        bl mmu_sint

        add zil, $5
        b cpu_ret

        .global cpu_step
cpu_step:
        /* Continue if mid-instruction */
        tst zil, $0x00800000
        bne cpu_step_cont

        /* Process interrupts */
        tst zil, $(intM << intO)
        bicne zil, $0x02000000
        tstne zil, $(intE << intO)
        bne cpu_int

        /* Loop for HALT/STOP */
        tst zil, $0x03000000
        addne zil, $1
        bne cpu_ret

        /* Load Instruction */
        bl mmu_ri
        ldr pc, [zop, r0, lsl $2]

cpu_step_cont:
        bic zil, $0x00800000
        ldr r1, =stash
        ldmfd r1, {r0, pc}

cpu_inst_b:
        orr zil, $0x00800000
        ldr r1, =stash
        stmea r1, {r0, lr}
        b cpu_ret

cpu_oam_bug_double:
        @ Check register range
        subs r1, $0xFE00
        rsbhss r1, $0x00FF
        bhs cpu_oam_bug_lcd

cpu_oam_bug:
        @ Check register range
        subs r0, $0xFE00
        rsbhss r0, $0x00FF
        blo cpu_ret

cpu_oam_bug_lcd:
        @ Check LCD mode
        and r0, zil, $0x6000
        cmp r0, $0x4000
        bne cpu_ret

        @ Corrupt (some) OAM
        ldr r0, =$0xFE08CCCC
        bl mmu_wh
        ldr r0, =$0xFE0ACCCC
        bl mmu_wh

        b cpu_ret

        .ltorg    @ keep literal pool close

/* SPECIAL INSTRUCTIONS */

opNI:
        b cpu_exception

opEXIT:
        mov r0, zra
        add zil, $1
        add zpc, $0x00010000
        b cpu_exit

/* INSTRUCTIONS */

opNOP:   @0x00
        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDBCnn:@0x01
        bl mmu_rih1
        lsl zbc, r0, $0x10

        add zil, $3
        add zpc, $0x00030000
        b cpu_ret

opLDBCA: @0x02
        orr r0, zra, zbc
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opIBC:   @0x03
        lsr r0, zbc, $0x10
        add zbc, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_oam_bug

opIB:    @0x04
        bic zrf, $flZNH         @ reset zero, subtract and half-carry

        add zbc, $0x01000000
        tst zbc, $0x0F000000    @ if lower nibble is zero
        orreq zrf, $flH                 @ set half-carry
        tst zbc, $0xFF000000    @ if result is completely zero
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opDB:    @0x05
        orr zrf, $flZNH         @ set zero, subtract and half-carry

        tst zbc, $0x0F000000    @ if lower nibble is not completely zero
        bicne zrf, $flH                 @ reset half-carry
        add zbc, $0xFF000000
        tst zbc, $0xFF000000    @ if result is not completely zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDBn:  @0x06
        bl mmu_ri1

        bic zbc, $0xFF000000
        orr zbc, r0, lsl $0x18

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opRLCA:  @0x07
        eor zrf, zrf            @ reset all flags

        lsl zra, $0x01
        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry
        orrne zra, $0x01                @ set bit 0
        andne zra, $0xFF        @ clear any carried bit(s)

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDnnSP:@0x08
        bl mmu_rih1
        lsl r0, $0x10
        orr r0, zsp, lsr $0x10
        bl mmu_wh

        add zil, $5
        add zpc, $0x00030000
        b cpu_ret

opAHLBC: @0x09
        bic zrf, $flN           @ reset subtract

        lsr r0, zhl, $0x10              @ put HL in r0
        lsr r1, zbc, $0x10              @ put BC in r1
        add lr, r0, r1

        eor r1, r1, lr
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x1000         @ if bit 12 is set
        orrne zrf, $flH                 @ set half-carry
        biceq zrf, $flH                 @ reset half-carry

        tst r1, $0x10000        @ if bit 16 is set
        orrne zrf, $flC                 @ set full-carry
        biceq zrf, $flC                 @ reset full-carry

        lsl zhl, lr, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDABC: @0x0A
        lsr r0, zbc, $0x10
        bl mmu_rb

        mov zra, r0

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opDBC:   @0x0B
        lsr r0, zbc, $0x10
        sub zbc, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_oam_bug

opIC:    @0x0C
        bic zrf, $flZNH         @ reset zero, subtract and half-carry

        add zbc, $0x00010000
        tst zbc, $0x000F0000    @ if lower nibble is zero
        orreq zrf, $flH                 @ set half-carry
        tst zbc, $0x00FF0000    @ if result is completely zero
        orreq zrf, $flZ                 @ set zero
        subeq zbc, $0x01000000

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opDC:    @0x0D
        orr zrf, $flZNH         @ set zero, subtract and half-carry

        ror zbc, $0x18

        tst zbc, $0x0F000000    @ if lower nibble is not completely zero
        bicne zrf, $flH                 @ reset half-carry
        add zbc, $0xFF000000
        tst zbc, $0xFF000000    @ if result is not completely zero
        bicne zrf, $flZ                 @ reset zero

        ror zbc, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDCn:  @0x0E
        bl mmu_ri1

        bic zbc, $0x00FF0000
        orr zbc, r0, lsl $0x10

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opRRCA:  @0x0F
        eor zrf, zrf            @ reset all flags

        tst zra, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry
        orrne zra, $0x100               @ set bit 8

        lsr zra, $0x01

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opSTOP:  @0x10
        orr zil, $0x01000000

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDDEnn:@0x11
        bl mmu_rih1
        lsl zde, r0, $0x10

        add zil, $3
        add zpc, $0x00030000
        b cpu_ret

opLDDEA: @0x12
        orr r0, zra, zde
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opIDE:   @0x13
        lsr r0, zde, $0x10
        add zde, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_oam_bug

opID:    @0x14
        bic zrf, $flZNH         @ reset zero, subtract and half-carry

        add zde, $0x01000000
        tst zde, $0x0F000000    @ if lower nibble is zero
        orreq zrf, $flH                 @ set half-carry
        tst zde, $0xFF000000    @ if result is completely zero
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opDD:    @0x15
        orr zrf, $flZNH         @ set zero, subtract and half-carry

        tst zde, $0x0F000000    @ if lower nibble is not completely zero
        bicne zrf, $flH                 @ reset half-carry
        add zde, $0xFF000000
        tst zde, $0xFF000000    @ if result is not completely zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDDn:  @0x16
        bl mmu_ri1

        bic zde, $0xFF000000
        orr zde, r0, lsl $0x18

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opRLA:   @0x17
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        lsl zra, $0x01
        orrne zra, $0x01

        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry
        andne zra, $0xFF        @ clear any carried bit(s)

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opJRn:   @0x18
        bl mmu_ri1
        lsl r0, $0x18
        add zpc, r0, asr $0x08

        add zil, $3
        add zpc, $0x00020000
        b cpu_ret

opAHLDE: @0x19
        bic zrf, $flN           @ reset subtract

        lsr r0, zhl, $0x10              @ put HL in r0
        lsr r1, zde, $0x10              @ put BC in r1
        add lr, r0, r1

        eor r1, r1, lr
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x1000         @ if bit 12 is set
        orrne zrf, $flH                 @ set half-carry
        biceq zrf, $flH                 @ reset half-carry

        tst r1, $0x10000        @ if bit 16 is set
        orrne zrf, $flC                 @ set full-carry
        biceq zrf, $flC                 @ reset full-carry

        lsl zhl, lr, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDADE: @0x1A
        lsr r0, zde, $0x10
        bl mmu_rb

        mov zra, r0

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opDDE:   @0x1B
        lsr r0, zde, $0x10
        sub zde, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_oam_bug

opIE:    @0x1C
        bic zrf, $flZNH         @ reset zero, subtract and half-carry

        add zde, $0x00010000
        tst zde, $0x000F0000    @ if lower nibble is zero
        orreq zrf, $flH                 @ set half-carry
        tst zde, $0x00FF0000    @ if result is completely zero
        orreq zrf, $flZ                 @ set zero
        subeq zde, $0x01000000

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opDE:    @0x1D
        orr zrf, $flZNH         @ set zero, subtract and half-carry

        ror zde, $0x18

        tst zde, $0x0F000000    @ if lower nibble is not completely zero
        bicne zrf, $flH                 @ reset half-carry
        add zde, $0xFF000000
        tst zde, $0xFF000000    @ if result is not completely zero
        bicne zrf, $flZ                 @ reset zero

        ror zde, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDEn:  @0x1E
        bl mmu_ri1

        bic zde, $0x00FF0000
        orr zde, r0, lsl $0x10

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opRRA:   @0x1F
        tst zrf, $flC           @ if carry
        orrne zra, $0x100               @ set bit 8

        eor zrf, zrf            @ reset all flags

        tst zra, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsr zra, $0x01

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opJRNZn: @0x20
        add zil, $2

        tst zrf, $flZ
        addne zpc, $0x00020000
        bne cpu_ret

        add zil, $1

        bl mmu_ri1
        lsl r0, $0x18
        add zpc, r0, asr $0x08
        add zpc, $0x00020000

        b cpu_ret

opLDHLnn:@0x21
        bl mmu_rih1
        lsl zhl, r0, $0x10

        add zil, $3
        add zpc, $0x00030000
        b cpu_ret

opLDHLiA:@0x22
        orr r0, zra, zhl
        bl mmu_wb

        add zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opIHL:   @0x23
        lsr r0, zhl, $0x10
        add zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_oam_bug

opIH:    @0x24
        bic zrf, $flZNH         @ reset zero, subtract and half-carry

        add zhl, $0x01000000
        tst zhl, $0x0F000000    @ if lower nibble is zero
        orreq zrf, $flH                 @ set half-carry
        tst zhl, $0xFF000000    @ if result is completely zero
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opDH:    @0x25
        orr zrf, $flZNH         @ set zero, subtract and half-carry

        tst zhl, $0x0F000000    @ if lower nibble is not completely zero
        bicne zrf, $flH                 @ reset half-carry
        add zhl, $0xFF000000
        tst zhl, $0xFF000000    @ if result is not completely zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDHn:  @0x26
        bl mmu_ri1

        bic zhl, $0xFF000000
        orr zhl, r0, lsl $0x18

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opDAA:   @0x27
        tst zrf, $flN
        bne opDAA_neg

        tst zrf, $flH           @ if half-carry
        andeq r0, zra, $0xF
        cmp r0, $0x0A           @ or lower nibble of A > 9
        addge zra, $0x06                @ add 6

        tst zrf, $flC           @ if carry
        cmpeq zra, $0xA0        @ or A > 159
        addge zra, $0x60                @ add 96

        b opDAA_end

opDAA_neg:
        tst zrf, $flH           @ if half-carry
        subne r0, zra, $0x06            @ subtract 6
        andne zra, r0, $0xFF

        tst zrf, $flC           @ if carry
        subne zra, $0x60                @ subtract 96

opDAA_end:
        cmp zra, $0x100
        orrge zrf, $flC         @ set carry

        ands zra, $0xFF
        orreq zrf, $flZ         @ set zero
        bicne zrf, $flZ         @ reset zero

        bic zrf, $flH           @ reset half-carry

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opJRZn:  @0x28
        add zil, $2

        tst zrf, $flZ
        addeq zpc, $0x00020000
        beq cpu_ret

        add zil, $1

        bl mmu_ri1
        lsl r0, $0x18
        add zpc, r0, asr $0x08
        add zpc, $0x00020000

        b cpu_ret

opAHLHL: @0x29
        bic zrf, $flNHC         @ reset subtract, half-carry and full-carry

        tst zhl, $0x08000000    @ if bit 11 is set
        orrne zrf, $flH                 @ set half-carry

        adds zhl, zhl
        orrcs zrf, $flC                 @ set full-carry

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDAHLi:@0x2A
        lsr r0, zhl, $0x10
        bl mmu_rb
        mov zra, r0

        lsr r0, zhl, $0x10

        add zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_oam_bug

opDHL:   @0x2B
        lsr r0, zhl, $0x10
        sub zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_oam_bug

opIL:    @0x2C
        bic zrf, $flZNH         @ reset zero, subtract and half-carry

        add zhl, $0x00010000
        tst zhl, $0x000F0000    @ if lower nibble is zero
        orreq zrf, $flH                 @ set half-carry
        tst zhl, $0x00FF0000    @ if result is completely zero
        orreq zrf, $flZ                 @ set zero
        subeq zhl, $0x01000000

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opDL:    @0x2D
        orr zrf, $flZNH         @ set zero, subtract and half-carry

        ror zhl, $0x18

        tst zhl, $0x0F000000    @ if lower nibble is not completely zero
        bicne zrf, $flH                 @ reset half-carry
        add zhl, $0xFF000000
        tst zhl, $0xFF000000    @ if result is not completely zero
        bicne zrf, $flZ                 @ reset zero

        ror zhl, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDLn:  @0x2E
        bl mmu_ri1

        bic zhl, $0x00FF0000
        orr zhl, r0, lsl $0x10

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opCPL:   @0x2F
        mvn zra, zra
        and zra, $0xFF
        orr zrf, $flNH

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opJRNCn: @0x30
        add zil, $2

        tst zrf, $flC
        addne zpc, $0x00020000
        bne cpu_ret

        add zil, $1

        bl mmu_ri1
        lsl r0, $0x18
        add zpc, r0, asr $0x08
        add zpc, $0x00020000

        b cpu_ret

opLDSPnn:@0x31
        bl mmu_rih1
        lsl zsp, r0, $0x10

        add zil, $3
        add zpc, $0x00030000
        b cpu_ret

opLDHLdA:@0x32
        orr r0, zra, zhl
        bl mmu_wb

        sub zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opISP:   @0x33
        lsr r0, zsp, $0x10
        add zsp, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_oam_bug

opIHLm:  @0x34
        lsr r0, zhl, $0x10
        bl mmu_rb

        lsl r0, $0x18

        add zil, $1
        bl cpu_inst_b

        bic zrf, $flZNH         @ reset zero, subtract and half-carry

        adds r0, $0x01000000
        orreq zrf, $flZ                 @ set zero
        tst r0, $0x0F000000     @ if lower nibble is zero
        orreq zrf, $flH                 @ set half-carry

        orr r0, zhl, r0, lsr $0x18
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opDHLm:  @0x35
        lsr r0, zhl, $0x10
        bl mmu_rb

        lsl r0, $0x18

        add zil, $1
        bl cpu_inst_b

        orr zrf, $flZNH         @ set zero, subtract and half-carry

        tst r0, $0x0F000000     @ if lower nibble is not completely zero
        bicne zrf, $flH                 @ reset half-carry
        adds r0, $0xFF000000
        bicne zrf, $flZ                 @ reset zero

        orr r0, zhl, r0, lsr $0x18
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDHLn: @0x36
        add zil, $1
        bl cpu_inst_b

        add r0, zpc, $0x00010000
        lsr r0, $0x10
        bl mmu_rb
        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opSCF:   @0x37
        bic zrf, $flNH          @ reset subtract and half-carry
        orr zrf, $flC           @ set carry

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opJRCn: @0x38
        add zil, $2

        tst zrf, $flC
        addeq zpc, $0x00020000
        beq cpu_ret

        add zil, $1

        bl mmu_ri1
        lsl r0, $0x18
        add zpc, r0, asr $0x08
        add zpc, $0x00020000

        b cpu_ret

opAHLSP: @0x39
        bic zrf, $flNHC         @ reset subtract, half-carry and full-carry

        adds lr, zhl, zsp
        orrcs zrf, $flC

        eor zhl, lr
        eor zhl, zsp
        tst zhl, $0x10000000    @ if bit 12 is set
        orrne zrf, $flH                 @ set half-carry

        mov zhl, lr

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDAHLd:@0x3A
        lsr r0, zhl, $0x10
        bl mmu_rb
        mov zra, r0

        lsr r0, zhl, $0x10

        sub zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_oam_bug

opDSP:   @0x3B
        lsr r0, zsp, $0x10
        sub zsp, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_oam_bug

opIA:    @0x3C
        bic zrf, $flN           @ reset subtract

        add r0, zra, $1

        eor r1, r0, zra
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        biceq zrf, $flH                 @ reset half-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opDA:    @0x3D
        orr zrf, $flN           @ set subtract

        add r0, zra, $0xFF      @ subtract 1

        eor r1, zra, r0
        eor r1, r1, $0xFF       @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        bicne zrf, $flH                 @ reset half-carry
        orreq zrf, $flH                 @ set half-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDAn:  @0x3E
        bl mmu_ri1

        mov zra, r0

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opCCF:   @0x3F
        bic zrf, $flNH          @ reset subtract and half-carry
        eor zrf, $flC           @ complement carry

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDBB:  @0x40
        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDBC:  @0x41
        bic zbc, $0xFF000000
        orr zbc, zbc, lsl $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDBD:  @0x42
        lsl zbc, $0x08
        orr zbc, zde, lsr $0x18
        ror zbc, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDBE:  @0x43
        bic zbc, $0xFF000000
        orr zbc, zde, lsl $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDBH:  @0x44
        lsl zbc, $0x08
        orr zbc, zhl, lsr $0x18
        ror zbc, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDBL:  @0x45
        bic zbc, $0xFF000000
        orr zbc, zhl, lsl $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDBHL: @0x46
        lsr r0, zhl, $0x10
        bl mmu_rb

        bic zbc, $0xFF000000
        orr zbc, r0, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDBA:  @0x47
        bic zbc, $0xFF000000
        orr zbc, zra, lsl $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDCB:  @0x48
        bic zbc, $0x00FF0000
        orr zbc, zbc, lsr $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDCC:  @0x49
        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDCD:  @0x4A
        bic zbc, $0x00FF0000
        orr zbc, zde, lsr $0x08
        bic zbc, $0x0000FF00

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDCE:  @0x4B
        lsr zbc, $0x18
        orr zbc, zde, lsl $0x08
        ror zbc, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDCH:  @0x4C
        bic zbc, $0x00FF0000
        orr zbc, zhl, lsr $0x08
        bic zbc, $0x0000FF00

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDCL:  @0x4D
        lsr zbc, $0x18
        orr zbc, zhl, lsl $0x08
        ror zbc, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDCHL: @0x4E
        lsr r0, zhl, $0x10
        bl mmu_rb

        bic zbc, $0x00FF0000
        orr zbc, r0, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDCA:  @0x4F
        bic zbc, $0x00FF0000
        orr zbc, zra, lsl $0x10

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDDB:  @0x50
        lsl zde, $0x08
        orr zde, zbc, lsr $0x18
        ror zde, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDDC:  @0x51
        bic zde, $0xFF000000
        orr zde, zbc, lsl $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDDD:  @0x52
        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDDE:  @0x53
        bic zde, $0xFF000000
        orr zde, zde, lsl $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDDH:  @0x54
        lsl zde, $0x08
        orr zde, zhl, lsr $0x18
        ror zde, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDDL:  @0x55
        bic zde, $0xFF000000
        orr zde, zhl, lsl $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDDHL: @0x56
        lsr r0, zhl, $0x10
        bl mmu_rb

        bic zde, $0xFF000000
        orr zde, r0, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDDA:  @0x57
        bic zde, $0xFF000000
        orr zde, zra, lsl $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDEB:  @0x58
        bic zde, $0x00FF0000
        orr zde, zbc, lsr $0x08
        bic zde, $0x0000FF00

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDEC:  @0x59
        lsr zde, $0x18
        orr zde, zbc, lsl $0x08
        ror zde, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDED:  @0x5A
        bic zde, $0x00FF0000
        orr zde, zde, lsr $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDEE:  @0x5B
        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDEH:  @0x5C
        bic zde, $0x00FF0000
        orr zde, zhl, lsr $0x08
        bic zde, $0x0000FF00

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDEL:  @0x5D
        lsr zde, $0x18
        orr zde, zhl, lsl $0x08
        ror zde, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDEHL: @0x5E
        lsr r0, zhl, $0x10
        bl mmu_rb

        bic zde, $0x00FF0000
        orr zde, r0, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDEA:  @0x5F
        bic zde, $0x00FF0000
        orr zde, zra, lsl $0x10

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDHB:  @0x60
        lsl zhl, $0x08
        orr zhl, zbc, lsr $0x18
        ror zhl, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDHC:  @0x61
        bic zhl, $0xFF000000
        orr zhl, zbc, lsl $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDHD:  @0x62
        lsl zhl, $0x08
        orr zhl, zde, lsr $0x18
        ror zhl, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDHE:  @0x63
        bic zhl, $0xFF000000
        orr zhl, zde, lsl $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDHH:  @0x64
        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDHL:  @0x65
        bic zhl, $0xFF000000
        orr zhl, zhl, lsl $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDHHL: @0x66
        lsr r0, zhl, $0x10
        bl mmu_rb

        bic zhl, $0xFF000000
        orr zhl, r0, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDHA:  @0x67
        bic zhl, $0xFF000000
        orr zhl, zra, lsl $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDLB:  @0x68
        bic zhl, $0x00FF0000
        orr zhl, zbc, lsr $0x08
        bic zhl, $0x0000FF00

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDLC:  @0x69
        lsr zhl, $0x18
        orr zhl, zbc, lsl $0x08
        ror zhl, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDLD:  @0x6A
        bic zhl, $0x00FF0000
        orr zhl, zde, lsr $0x08
        bic zhl, $0x0000FF00

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDLE:  @0x6B
        lsr zhl, $0x18
        orr zhl, zde, lsl $0x08
        ror zhl, $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDLH:  @0x6C
        bic zhl, $0x00FF0000
        orr zhl, zhl, lsr $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDLL:  @0x6D
        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDLHL: @0x6E
        lsr r0, zhl, $0x10
        bl mmu_rb

        bic zhl, $0x00FF0000
        orr zhl, r0, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDLA:  @0x6F
        bic zhl, $0x00FF0000
        orr zhl, zra, lsl $0x10

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDHLB: @0x70
        orr r0, zhl, zbc, lsr $0x18
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDHLC: @0x71
        orr r0, zhl, zbc, lsr $0x10
        bic r0, $0x0000FF00
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDHLD: @0x72
        orr r0, zhl, zde, lsr $0x18
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDHLE: @0x73
        orr r0, zhl, zde, lsr $0x10
        bic r0, $0x0000FF00
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDHLH: @0x74
        orr r0, zhl, zhl, lsr $0x18
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDHLL: @0x75
        orr r0, zhl, zhl, lsr $0x10
        bic r0, $0x0000FF00
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opHALT:  @0x76
        orr zil, $0x02000000

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDHLA: @0x77
        orr r0, zra, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDAB:  @0x78
        lsr zra, zbc, $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDAC:  @0x79
        lsr zra, zbc, $0x10
        and zra, $0xFF

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDAD:  @0x7A
        lsr zra, zde, $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDAE:  @0x7B
        lsr zra, zde, $0x10
        and zra, $0xFF

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDAH:  @0x7C
        lsr zra, zhl, $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDAL:  @0x7D
        lsr zra, zhl, $0x10
        and zra, $0x000000FF

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opLDAHL: @0x7E
        lsr r0, zhl, $0x10
        bl mmu_rb

        mov zra, r0

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDAA:  @0x7F
        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAAB:   @0x80
        eor zrf, zrf            @ reset all flags

        add r0, zra, zbc, lsr $0x18

        eor r1, r0, zra
        eor r1, r1, zbc, lsr $0x18 @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAAC:   @0x81
        eor zrf, zrf            @ reset all flags

        lsr r0, zbc, $0x10
        and r0, $0xFF

        add r1, zra, r0

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAAD:   @0x82
        eor zrf, zrf            @ reset all flags

        add r0, zra, zde, lsr $0x18

        eor r1, r0, zra
        eor r1, r1, zde, lsr $0x18 @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAAE:   @0x83
        eor zrf, zrf            @ reset all flags

        lsr r0, zde, $0x10
        and r0, $0xFF

        add r1, zra, r0

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAAH:   @0x84
        eor zrf, zrf            @ reset all flags

        add r1, zra, zhl, lsr $0x18

        eor r0, r1, zra
        eor r0, zhl, lsr $0x18  @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAAL:   @0x85
        eor zrf, zrf            @ reset all flags

        lsr r0, zhl, $0x10
        and r0, $0xFF

        add r1, zra, r0

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAAHL:  @0x86
        lsr r0, zhl, $0x10
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        add r1, zra, r0

        eor r0, r0, zra
        eor r0, r0, r1          @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opAAA:   @0x87
        eor zrf, zrf            @ reset all flags

        add zra, zra

        tst zra, $0x10          @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, $0xFF                 @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAcAB:  @0x88
        lsr r1, zbc, $0x18

        tst zrf, $flC
        addne r1, $1

        eor zrf, zrf            @ reset all flags

        add r1, zra

        eor r0, r1, zra
        eor r0, zbc, lsr $0x18  @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAcAC:  @0x89
        lsr r0, zbc, $0x10
        and r0, $0xFF

        tst zrf, $flC
        moveq r1, r0
        addne r1, r0, $1

        eor zrf, zrf            @ reset all flags

        add r1, zra

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAcAD:  @0x8A
        lsr r1, zde, $0x18

        tst zrf, $flC
        addne r1, $1

        eor zrf, zrf            @ reset all flags

        add r1, zra

        eor r0, r1, zra
        eor r0, zde, lsr $0x18  @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAcAE:  @0x8B
        lsr r0, zde, $0x10
        and r0, $0xFF

        tst zrf, $flC
        moveq r1, r0
        addne r1, r0, $1

        eor zrf, zrf            @ reset all flags

        add r1, zra

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAcAH:  @0x8C
        lsr r1, zhl, $0x18

        tst zrf, $flC
        addne r1, $1

        eor zrf, zrf            @ reset all flags

        add r1, zra

        eor r0, r1, zra
        eor r0, zhl, lsr $0x18  @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAcAL:  @0x8D
        lsr r0, zhl, $0x10
        and r0, $0xFF

        tst zrf, $flC
        moveq r1, r0
        addne r1, r0, $1

        eor zrf, zrf            @ reset all flags

        add r1, zra

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opAcAHL: @0x8E
        lsr r0, zhl, $0x10
        bl mmu_rb

        tst zrf, $flC
        moveq r1, r0
        addne r1, r0, $1

        eor zrf, zrf            @ reset all flags

        add r1, zra

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opAcAA:  @0x8F
        add zra, zra

        tst zrf, $flC
        addne zra, $1

        eor zrf, zrf            @ reset all flags

        tst zra, $0x10          @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, $0xFF                 @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opSAB:   @0x90
        mov zrf, $flN           @ set only subtract

        mvn r1, zbc, lsr $0x18
        add r1, $1              @ 2's compliment
        add r0, zra, r1

        eor r1, r0, zra
        eor r1, r1, zbc, lsr $0x18 @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opSAC:   @0x91
        mov zrf, $flN           @ set only subtract

        lsr r0, zbc, $0x10
        and r0, $0xFF

        mvn r1, r0
        add r1, $1              @ 2's compliment
        add r1, zra

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opSAD:   @0x92
        mov zrf, $flN           @ set only subtract

        mvn r1, zde, lsr $0x18
        add r1, $1              @ 2's compliment
        add r0, zra, r1

        eor r1, r0, zra
        eor r1, r1, zde, lsr $0x18 @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opSAE:   @0x93
        mov zrf, $flN           @ set only subtract

        lsr r0, zde, $0x10
        and r0, $0xFF

        mvn r1, r0
        add r1, $1              @ 2's compliment
        add r1, zra

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opSAH:   @0x94
        mov zrf, $flN           @ set only subtract

        mvn r0, zhl, lsr $0x18
        add r0, $1              @ 2's compliment
        add r1, zra, r0

        eor r0, r1, zra
        eor r0, zhl, lsr $0x18  @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opSAL:   @0x95
        mov zrf, $flN           @ set only subtract

        lsr r0, zhl, $0x10
        and r0, $0xFF

        mvn r1, r0
        add r1, $1              @ 2's compliment
        add r1, zra

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opSAHL:  @0x96
        lsr r0, zhl, $0x10
        bl mmu_rb

        mov zrf, $flN           @ set only subtract

        mvn r1, r0
        add r1, $1              @ 2's compliment
        add r1, zra

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opSAA:   @0x97
        mov zrf, $flN           @ set only subtract
        orr zrf, $flZ           @ set zero

        mov zra, $0

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opScAB:  @0x98
        mvn r1, zbc, lsr $0x18
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r0, zra, r1

        mov zrf, $flN           @ set only subtract

        eor r1, r0, zra
        eor r1, r1, zbc, lsr $0x18 @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opScAC:  @0x99
        lsr r0, zbc, $0x10
        and r0, $0xFF

        mvn r1, r0
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r1, zra

        mov zrf, $flN           @ set only subtract

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opScAD:  @0x9A
        mvn r1, zde, lsr $0x18
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r0, zra, r1

        mov zrf, $flN           @ set only subtract

        eor r1, r0, zra
        eor r1, r1, zde, lsr $0x18 @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opScAE:  @0x9B
        lsr r0, zde, $0x10
        and r0, $0xFF

        mvn r1, r0
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r1, zra

        mov zrf, $flN           @ set only subtract

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opScAH:  @0x9C
        mvn r0, zhl, lsr $0x18
        tst zrf, $flC
        addeq r0, $1            @ 2's compliment
        add r1, zra, r0

        mov zrf, $flN           @ set only subtract

        eor r0, r1, zra
        eor r0, zhl, lsr $0x18  @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opScAL:  @0x9D
        lsr r0, zhl, $0x10
        and r0, $0xFF

        mvn r1, r0
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r1, zra

        mov zrf, $flN           @ set only subtract

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opScAHL: @0x9E
        lsr r0, zhl, $0x10
        bl mmu_rb

        mvn r1, r0
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r1, zra

        mov zrf, $flN           @ set only subtract

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opScAA:  @0x9F
        tst zrf, $flC
        moveq zra, $0x00
        moveq zrf, $flZ
        movne zra, $0xFF
        movne zrf, $flC
        orrne zrf, $flH

        orr zrf, $flN

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opANAB:  @0xA0
        mov zrf, $flH           @ set only half-carry

        ands zra, zbc, lsr $0x18
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opANAC:  @0xA1
        mov zrf, $flH           @ set only half-carry

        ands zra, zbc, lsr $0x10
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opANAD:  @0xA2
        mov zrf, $flH           @ set only half-carry

        ands zra, zde, lsr $0x18
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opANAE:  @0xA3
        mov zrf, $flH           @ set only half-carry

        ands zra, zde, lsr $0x10
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opANAH:  @0xA4
        mov zrf, $flH           @ set only half-carry

        ands zra, zhl, lsr $0x18
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opANAL:  @0xA5
        mov zrf, $flH           @ set only half-carry

        ands zra, zhl, lsr $0x10
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opANAHL: @0xA6
        lsr r0, zhl, $0x10
        bl mmu_rb

        mov zrf, $flH           @ set only half-carry

        ands zra, r0
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opANAA:  @0xA7
        mov zrf, $flH           @ set only half-carry

        ands zra, zra
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opXOAB:  @0xA8
        eor zrf, zrf            @ reset all flags

        eors zra, zbc, lsr $0x18
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opXOAC:  @0xA9
        eor zrf, zrf            @ reset all flags

        eor zra, zbc, lsr $0x10
        bics zra, $0x0000FF00
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opXOAD:  @0xAA
        eor zrf, zrf            @ reset all flags

        eors zra, zde, lsr $0x18
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opXOAE:  @0xAB
        eor zrf, zrf            @ reset all flags

        eor zra, zde, lsr $0x10
        bics zra, $0x0000FF00
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opXOAH:  @0xAC
        eor zrf, zrf            @ reset all flags

        eors zra, zhl, lsr $0x18
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opXOAL:  @0xAD
        eor zrf, zrf            @ reset all flags

        eor zra, zhl, lsr $0x10
        bics zra, $0x0000FF00
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opXOAHL: @0xAE
        lsr r0, zhl, $0x10
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        eors zra, r0
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opXOAA:  @0xAF
        eor zrf, zrf            @ reset all flags

        eors zra, zra
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opORAB:  @0xB0
        eor zrf, zrf            @ reset all flags

        orrs zra, zbc, lsr $0x18
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opORAC:  @0xB1
        eor zrf, zrf            @ reset all flags

        orr zra, zbc, lsr $0x10
        bics zra, $0x0000FF00
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opORAD:  @0xB2
        eor zrf, zrf            @ reset all flags

        orrs zra, zde, lsr $0x18
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opORAE:  @0xB3
        eor zrf, zrf            @ reset all flags

        orr zra, zde, lsr $0x10
        bics zra, $0x0000FF00
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opORAH:  @0xB4
        eor zrf, zrf            @ reset all flags

        orrs zra, zhl, lsr $0x18
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opORAL:  @0xB5
        eor zrf, zrf            @ reset all flags

        orr zra, zhl, lsr $0x10
        bics zra, $0x0000FF00
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opORAHL: @0xB6
        lsr r0, zhl, $0x10
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        orrs zra, r0
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opORAA:  @0xB7
        eor zrf, zrf            @ reset all flags

        orrs zra, zra
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opCAB:   @0xB8
        mov zrf, $flN           @ set only subtract

        mvn r0, zbc, lsr $0x18
        add r0, $1              @ 2's compliment
        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zbc, lsr $0x18 @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opCAC:   @0xB9
        mov zrf, $flN           @ set only subtract

        lsr r0, zbc, $0x10
        and r0, $0xFF

        mvn r1, r0
        add r1, $1              @ 2's compliment
        add r1, zra

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r1, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opCAD:   @0xBA
        mov zrf, $flN           @ set only subtract

        mvn r0, zde, lsr $0x18
        add r0, $1              @ 2's compliment
        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zde, lsr $0x18 @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opCAE:   @0xBB
        mov zrf, $flN           @ set only subtract

        lsr r0, zde, $0x10
        and r0, $0xFF

        mvn r1, r0
        add r1, $1              @ 2's compliment
        add r1, zra

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r1, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opCAH:   @0xBC
        mov zrf, $flN           @ set only subtract

        mvn r1, zhl, lsr $0x18
        add r1, $1              @ 2's compliment
        add r1, zra

        eor r0, r1, zra
        eor r0, zhl, lsr $0x18  @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r1, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opCAL:   @0xBD
        mov zrf, $flN           @ set only subtract

        lsr r0, zhl, $0x10
        and r0, $0xFF

        mvn r1, r0
        add r1, $1              @ 2's compliment
        add r1, zra

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r1, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opCAHL:  @0xBE
        lsr r0, zhl, $0x10
        bl mmu_rb

        mov zrf, $flN           @ set only subtract

        mvn r1, r0
        add r1, $1              @ 2's compliment
        add r1, zra

        eor r0, zra
        eor r0, r1              @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r1, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opCAA:   @0xBF
        mov zrf, $flN           @ set only subtract
        orr zrf, $flZ           @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opRETNZ: @0xC0
        add zil, $2

        tst zrf, $flZ
        addne zpc, $0x00010000
        bne cpu_ret

        add zil, $3

        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsl zpc, r0, $0x10

        b cpu_ret

opPOPBC: @0xC1
        lsr r0, zsp, $0x10
        add zsp, $0x00020000
        bl mmu_rh

        lsl zbc, r0, $0x10

        lsr r0, zsp, $0x10
        sub r0, $0x01
        sub r1, r0, $0x01

        add zil, $3
        add zpc, $0x00010000
        b cpu_oam_bug_double

opJPNZnn:@0xC2
        add zil, $3

        tst zrf, $flZ
        addne zpc, $0x00030000
        bne cpu_ret

        add zil, $1

        bl mmu_rih1
        lsl zpc, r0, $0x10
        b cpu_ret

opJPnn:  @0xC3
        bl mmu_rih1
        lsl zpc, r0, $0x10

        add zil, $4
        b cpu_ret

opCNZnn: @0xC4
        add zil, $3

        tst zrf, $flZ
        addne zpc, $0x00030000
        bne cpu_ret

        add zil, $3

        bl mmu_rih1

        add r1, zpc, $0x00030000
        lsl zpc, r0, $0x10

        sub zsp, $0x00020000

        orr r0, zsp, r1, lsr $0x10
        bl mmu_wh

        b cpu_ret

opPUSBC: @0xC5
        sub zsp, $0x00020000
        orr r0, zsp, zbc, lsr $0x10
        bl mmu_wh

        lsr r0, zsp, $0x10
        add r0, $0x01
        add r1, r0, $0x01

        add zil, $4
        add zpc, $0x00010000
        b cpu_oam_bug_double

opAAn:   @0xC6
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        add r1, zra, r0

        eor r0, r0, zra
        eor r0, r0, r1          @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opR00H:  @0xC7
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00000000
        b cpu_ret

opRETZ:  @0xC8
        add zil, $2

        tst zrf, $flZ
        addeq zpc, $0x00010000
        beq cpu_ret

        add zil, $3

        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsl zpc, r0, $0x10

        b cpu_ret

opRET:   @0xC9
        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsl zpc, r0, $0x10

        add zil, $4
        b cpu_ret

opJPZnn: @0xCA
        add zil, $3

        tst zrf, $flZ
        addeq zpc, $0x00030000
        beq cpu_ret

        add zil, $1

        bl mmu_rih1
        lsl zpc, r0, $0x10
        b cpu_ret

opCBP:   @ 0xCB
        add zpc, $0x00010000

        /* Load CB Instruction */
        bl mmu_ri

        /* CB prefix opcode table follows primary */
        add r0, $0x100
        ldr pc, [zop, r0, lsl $2]

opCZnn:  @0xCC
        add zil, $3

        tst zrf, $flZ
        addeq zpc, $0x00030000
        beq cpu_ret

        add zil, $3

        bl mmu_rih1

        add r1, zpc, $0x00030000
        lsl zpc, r0, $0x10

        sub zsp, $0x00020000
        orr r0, zsp, r1, lsr $0x10
        bl mmu_wh

        b cpu_ret

opCnn:   @0xCD
        bl mmu_rih1

        add r1, zpc, $0x00030000
        lsl zpc, r0, $0x10

        sub zsp, $0x00020000
        orr r0, zsp, r1, lsr $0x10
        bl mmu_wh

        add zil, $6
        b cpu_ret

opAcAn:  @0xCE
        bl mmu_ri1

        tst zrf, $flC           @ handle possible carry
        moveq r1, r0
        addne r1, r0, $1

        eor zrf, zrf            @ reset all flags

        add r1, zra

        eor r0, r0, zra
        eor r0, r0, r1          @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opR08H:  @0xCF
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00080000
        b cpu_ret

opRETNC: @0xD0
        add zil, $2

        tst zrf, $flC
        addne zpc, $0x00010000
        bne cpu_ret

        add zil, $3

        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsl zpc, r0, $0x10

        b cpu_ret

opPOPDE: @0xD1
        lsr r0, zsp, $0x10
        add zsp, $0x00020000
        bl mmu_rh

        lsl zde, r0, $0x10

        lsr r0, zsp, $0x10
        sub r0, $0x01
        sub r1, r0, $0x01

        add zil, $3
        add zpc, $0x00010000
        b cpu_oam_bug

opJPNCnn:@0xD2
        add zil, $3

        tst zrf, $flC
        addne zpc, $0x00030000
        bne cpu_ret

        add zil, $1

        bl mmu_rih1
        lsl zpc, r0, $0x10
        b cpu_ret

opCNCnn: @0xD4
        add zil, $3

        tst zrf, $flC
        addne zpc, $0x00030000
        bne cpu_ret

        add zil, $3

        bl mmu_rih1

        add r1, zpc, $0x00030000
        lsl zpc, r0, $0x10

        sub zsp, $0x00020000
        orr r0, zsp, r1, lsr $0x10
        bl mmu_wh

        b cpu_ret

opPUSDE: @0xD5
        sub zsp, $0x00020000
        orr r0, zsp, zde, lsr $0x10
        bl mmu_wh

        add zil, $4
        add zpc, $0x00010000
        b cpu_ret

opSAn:   @0xD6
        bl mmu_ri1

        mov zrf, $flN           @ set only subtract

        mvn r1, r0
        add r1, $1              @ 2's compliment
        add r1, zra

        eor r0, r0, zra
        eor r0, r0, r1          @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opR10H:  @0xD7
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00100000
        b cpu_ret

opRETC:  @0xD8
        add zil, $2

        tst zrf, $flC
        addeq zpc, $0x00010000
        beq cpu_ret

        add zil, $3

        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsl zpc, r0, $0x10

        b cpu_ret

opRETI:  @0xD9
        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsl zpc, r0, $0x10

        orr zil, $(intE << intO)

        add zil, $4
        b cpu_ret

opJPCnn: @0xDA
        add zil, $3

        tst zrf, $flC
        addeq zpc, $0x00030000
        beq cpu_ret

        add zil, $1

        bl mmu_rih1
        lsl zpc, r0, $0x10
        b cpu_ret

opCCnn:  @0xDC
        add zil, $3

        tst zrf, $flC
        addeq zpc, $0x00030000
        beq cpu_ret

        add zil, $3

        bl mmu_rih1

        add r1, zpc, $0x00030000
        lsl zpc, r0, $0x10

        sub zsp, $0x00020000
        orr r0, zsp, r1, lsr $0x10
        bl mmu_wh

        b cpu_ret

opScAn:  @0xDE
        bl mmu_ri1

        mvn r1, r0
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r1, zra

        mov zrf, $flN           @ set only subtract

        eor r0, r0, zra
        eor r0, r0, r1          @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r1, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opR18H:  @0xDF
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00180000
        b cpu_ret

opLDFnA: @0xE0
        add zil, $1
        bl cpu_inst_b

        bl mmu_ri1
        orr r0, $0xFF00
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opPOPHL: @0xE1
        lsr r0, zsp, $0x10
        add zsp, $0x00020000
        bl mmu_rh

        lsl zhl, r0, $0x10

        add zil, $3
        add zpc, $0x00010000
        b cpu_oam_bug

opLDFCA: @0xE2
        orr r0, zbc, $0xFF000000
        orr r0, zra
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opPUSHL: @0xE5
        sub zsp, $0x00020000
        orr r0, zsp, zhl, lsr $0x10
        bl mmu_wh

        add zil, $4
        add zpc, $0x00010000
        b cpu_ret

opANAn:  @0xE6
        bl mmu_ri1

        mov zrf, $flH           @ set only half-carry

        ands zra, r0
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opR20H:  @0xE7
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00200000
        b cpu_ret

opASPn:  @0xE8
        bl mmu_ri1

        lsl r0, $0x18
        asr r0, $0x08

        eor zrf, zrf            @ reset all flags

        adds r1, r0, zsp

        eor r0, r0, zsp
        eor r0, r0, r1          @ XOR all three
        tst r0, $0x100000       @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x1000000      @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        mov zsp, r1

        add zil, $4
        add zpc, $0x00020000
        b cpu_ret

opJPHL:  @0xE9
        mov zpc, zhl

        add zil, $1
        b cpu_ret

opLDnnA: @0xEA
        add zil, $2
        bl cpu_inst_b

        bl mmu_rih1
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        add zil, $2
        add zpc, $0x00030000
        b cpu_ret

opXOAn:  @0xEE
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        eors zra, r0
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opR28H:  @0xEF
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00280000
        b cpu_ret

opLDAFn: @0xF0
        add zil, $1
        bl cpu_inst_b

        bl mmu_ri1
        orr r0, $0xFF00
        bl mmu_rb

        mov zra, r0

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opPOPAF: @0xF1
        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsr zra, r0, $0x08
        and zrf, r0, $flM

        add zil, $3
        add zpc, $0x00010000
        b cpu_ret

opLDAFC: @0xF2
        orr r0, zbc, $0xFF000000
        lsr r0, $0x10
        bl mmu_rb

        mov zra, r0

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opDI:    @0xF3
        bic zil, $(intE << intO)        @ Disable interrupts

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opPUSAF: @0xF5
        sub zsp, $0x00020000
        orr r0, zrf, zra, lsl $0x08
        orr r0, zsp
        bl mmu_wh

        add zil, $4
        add zpc, $0x00010000
        b cpu_ret

opORAn:  @0xF6
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        orrs zra, r0
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opR30H:  @0xF7
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00300000
        b cpu_ret

opLDHLSn:@0xF8
        @ NOTE: The docs are pretty unclear on the flags here.
        @ I'm guessing it is treated like a typical 8-bit signed add.

        bl mmu_ri1
        lsl r0, $0x18
        asr r0, $0x08

        eor zrf, zrf            @ reset all flags

        add zhl, zsp, r0

        eor r0, zsp
        eor r0, zhl             @ XOR all three
        tst r0, $0x100000       @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x1000000      @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        add zil, $3
        add zpc, $0x00020000
        b cpu_ret

opLDSHL: @0xF9
        mov zsp, zhl

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

opLDAnn: @0xFA
        add zil, $2
        bl cpu_inst_b

        bl mmu_rih1
        bl mmu_rb

        mov zra, r0

        add zil, $2
        add zpc, $0x00030000
        b cpu_ret

opEI:    @0xFB
        orr zil, $(intE << intO)        @ Enable interrupts

        add zil, $1
        add zpc, $0x00010000
        b cpu_ret

opCAn:   @0xFE
        bl mmu_ri1

        mov zrf, $flN           @ set only subtract

        mvn r1, r0
        add r1, $1              @ 2's compliment
        add r1, zra

        eor r0, r0, zra
        eor r0, r0, r1          @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r1, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00020000
        b cpu_ret

opR38H:  @0xFF
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00380000
        b cpu_ret

/* CB-PREFIX INSTRUCTIONS */

cbRLCB:  @0xCB00
        eor zrf, zrf            @ reset all flags

        and lr, zbc, $0xFF000000
        lsls lr, $0x01          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrcss lr, $0x01000000          @ set bit 0
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0xFF000000
        orr zbc, lr

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLCC:  @0xCB01
        eor zrf, zrf            @ reset all flags

        lsls lr, zbc, $0x09     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrcss lr, $0x01000000          @ set bit 0
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0x00FF0000
        orr zbc, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLCD:  @0xCB02
        eor zrf, zrf            @ reset all flags

        and lr, zde, $0xFF000000
        lsls lr, $0x01          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrcss lr, $0x01000000          @ set bit 0
        orreq zrf, $flZ                 @ set zero

        bic zde, $0xFF000000
        orr zde, lr

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLCE:  @0xCB03
        eor zrf, zrf            @ reset all flags

        lsls lr, zde, $0x09     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrcss lr, $0x01000000          @ set bit 0
        orreq zrf, $flZ                 @ set zero

        bic zde, $0x00FF0000
        orr zde, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLCH:  @0xCB04
        eor zrf, zrf            @ reset all flags

        and lr, zhl, $0xFF000000
        lsls lr, $0x01          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrcss lr, $0x01000000          @ set bit 0
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0xFF000000
        orr zhl, lr

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLCL:  @0xCB05
        eor zrf, zrf            @ reset all flags

        lsls lr, zhl, $0x09     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrcss lr, $0x01000000          @ set bit 0
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0x00FF0000
        orr zhl, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLCHL: @0xCB06
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        lsl r0, $1
        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set carry
        orrne r0, $0x01                 @ set bit 0

        ands r0, $0xFF          @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLCA:  @0xCB07
        eor zrf, zrf            @ reset all flags

        lsl zra, $1
        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry
        orrne zra, $0x01                @ set bit 0

        ands zra, $0xFF         @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRCB:  @0xCB08
        eor zrf, zrf            @ reset all flags

        lsrs lr, zbc, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrcss lr, $0x80                @ set bit 7
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0xFF000000
        orr zbc, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRCC:  @0xCB09
        eor zrf, zrf            @ reset all flags

        and lr, zbc, $0x00FF0000
        lsrs lr, $0x11          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrcss lr, $0x80                @ set bit 7
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0x00FF0000
        orr zbc, lr, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRCD:  @0xCB0A
        eor zrf, zrf            @ reset all flags

        lsrs lr, zde, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrcss lr, $0x80                @ set bit 7
        orreq zrf, $flZ                 @ set zero

        bic zde, $0xFF000000
        orr zde, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRCE:  @0xCB0B
        eor zrf, zrf            @ reset all flags

        and lr, zde, $0x00FF0000
        lsrs lr, $0x11          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrcss lr, $0x80                @ set bit 7
        orreq zrf, $flZ                 @ set zero

        bic zde, $0x00FF0000
        orr zde, lr, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRCH:  @0xCB0C
        eor zrf, zrf            @ reset all flags

        lsrs lr, zhl, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrcss lr, $0x80                @ set bit 7
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0xFF000000
        orr zhl, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRCL:  @0xCB0D
        eor zrf, zrf            @ reset all flags

        and lr, zhl, $0x00FF0000
        lsrs lr, $0x11          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrcss lr, $0x80                @ set bit 7
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0x00FF0000
        orr zhl, lr, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRCHL: @0xCB0E
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        add zil, $1
        bl cpu_inst_b

        eor zrf, zrf            @ reset all flags

        tst r0, $0x01           @ if bit 0 is set
        orrne zrf, $flC                 @ set carry
        orrne r0, $0x100                @ set bit 8

        lsrs r0, $1
        orreq zrf, $flZ         @ set zero

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRCA:  @0xCB0F
        eor zrf, zrf            @ reset all flags

        tst zra, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry
        orrne zra, $0x100               @ set bit 8

        lsrs zra, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLB:   @0xCB10
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        and lr, zbc, $0xFF000000
        orrne lr, $0x00800000
        lsls lr, $0x01          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0xFF000000
        orr zbc, lr

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLC:   @0xCB11
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        lsl lr, zbc, $0x08
        orrne lr, $0x00800000
        lsls lr, $0x01          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0x00FF0000
        orr zbc, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLD:   @0xCB12
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        and lr, zde, $0xFF000000
        orrne lr, $0x00800000
        lsls lr, $0x01          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zde, $0xFF000000
        orr zde, lr

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLE:   @0xCB13
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        lsl lr, zde, $0x08
        orrne lr, $0x00800000
        lsls lr, $0x01          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zde, $0x00FF0000
        orr zde, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLH:   @0xCB14
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        and lr, zhl, $0xFF000000
        orrne lr, $0x00800000
        lsls lr, $0x01          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0xFF000000
        orr zhl, lr

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLL:   @0xCB15
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        lsl lr, zhl, $0x08
        orrne lr, $0x00800000
        lsls lr, $0x01          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0x00FF0000
        orr zhl, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLHL:  @0xCB16
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        add zil, $1
        bl cpu_inst_b

        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        lsl r0, $1
        orrne r0, $0x01

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands r0, $0xFF          @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRLA:   @0xCB17
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        lsl zra, $1
        orrne zra, $0x01

        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands zra, $0xFF         @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRB:   @0xCB18
        and r0, zrf, $flC       @ save carry

        eor zrf, zrf            @ reset all flags

        lsrs lr, zbc, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrs lr, r0, lsl $0x03          @ set bit 7
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0xFF000000
        orr zbc, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRC:   @0xCB19
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        and lr, zbc, $0x00FF0000
        orrne lr, $0x01000000           @ set bit 7
        lsrs lr, $0x11          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0x00FF0000
        orr zbc, lr, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRD:   @0xCB1A
        and r0, zrf, $flC       @ save carry

        eor zrf, zrf            @ reset all flags

        lsrs lr, zde, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrs lr, r0, lsl $0x03          @ set bit 7
        orreq zrf, $flZ                 @ set zero

        bic zde, $0xFF000000
        orr zde, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRE:   @0xCB1B
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        and lr, zde, $0x00FF0000
        orrne lr, $0x01000000           @ set bit 7
        lsrs lr, $0x11          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zde, $0x00FF0000
        orr zde, lr, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRH:   @0xCB1C
        and r0, zrf, $flC       @ save carry

        eor zrf, zrf            @ reset all flags

        lsrs lr, zhl, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orrs lr, r0, lsl $0x03          @ set bit 7
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0xFF000000
        orr zhl, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRL:   @0xCB1D
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        and lr, zhl, $0x00FF0000
        orrne lr, $0x01000000           @ set bit 7
        lsrs lr, $0x11          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0x00FF0000
        orr zhl, lr, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRHL:  @0xCB1E
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        add zil, $1
        bl cpu_inst_b

        tst zrf, $flC           @ if carry
        orrne r0, $0x100                @ set bit 8

        eor zrf, zrf            @ reset all flags

        tst r0, $0x01           @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs r0, $1
        orreq zrf, $flZ         @ set zero

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRRA:   @0xCB1F
        tst zrf, $flC           @ if carry
        orrne zra, $0x100               @ set bit 8

        eor zrf, zrf            @ reset all flags

        tst zra, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zra, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSLAB:  @0xCB20
        eor zrf, zrf            @ reset all flags

        and lr, zbc, $0xFF000000
        lsls lr, $0x01          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0xFF000000
        orr zbc, lr

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSLAC:  @0xCB21
        eor zrf, zrf            @ reset all flags

        lsls lr, zbc, $0x09     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0x00FF0000
        orr zbc, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSLAD:  @0xCB22
        eor zrf, zrf            @ reset all flags

        and lr, zde, $0xFF000000
        lsls lr, $0x01          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zde, $0xFF000000
        orr zde, lr

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSLAE:  @0xCB23
        eor zrf, zrf            @ reset all flags

        lsls lr, zde, $0x09     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zde, $0x00FF0000
        orr zde, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSLAH:  @0xCB24
        eor zrf, zrf            @ reset all flags

        and lr, zhl, $0xFF000000
        lsls lr, $0x01          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0xFF000000
        orr zhl, lr

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSLAL:  @0xCB25
        eor zrf, zrf            @ reset all flags

        lsls lr, zhl, $0x09     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0x00FF0000
        orr zhl, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSLAHL: @0xCB26
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        add zil, $1
        bl cpu_inst_b

        eor zrf, zrf           @ reset all flags

        lsl r0, $1

        tst r0, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands r0, $0xFF
        orreq zrf, $flZ         @ set zero

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSLAA:  @0xCB27
        eor zrf, zrf            @ reset all flags

        lsl zra, $1

        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands zra, $0xFF
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRAB:  @0xCB28
        eor zrf, zrf            @ reset all flags

        asrs lr, zbc, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0xFF000000
        orr zbc, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRAC:  @0xCB29
        eor zrf, zrf            @ reset all flags

        lsl lr, zbc, $0x08
        asrs lr, $0x19          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        lsl lr, $0x18
        bic zbc, $0x00FF0000
        orr zbc, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRAD:  @0xCB2A
        eor zrf, zrf            @ reset all flags

        asrs lr, zde, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zde, $0xFF000000
        orr zde, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRAE:  @0xCB2B
        eor zrf, zrf            @ reset all flags

        lsl lr, zde, $0x08
        asrs lr, $0x19          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        lsl lr, $0x18
        bic zde, $0x00FF0000
        orr zde, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRAH:  @0xCB2C
        eor zrf, zrf            @ reset all flags

        asrs lr, zhl, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0xFF000000
        orr zhl, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRAL:  @0xCB2D
        eor zrf, zrf            @ reset all flags

        lsl lr, zhl, $0x08
        asrs lr, $0x19          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        lsl lr, $0x18
        bic zhl, $0x00FF0000
        orr zhl, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRAHL: @0xCB2E
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        add zil, $1
        bl cpu_inst_b

        eor zrf, zrf            @ reset all flags

        tst r0, $0x01           @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs r0, $1
        orreq zrf, $flZ         @ set zero

        tst r0, $0x40
        orrne r0, $0x80

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRAA:  @0xCB2F
        eor zrf, zrf            @ reset all flags

        tst zra, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zra, $1
        orreq zrf, $flZ         @ set zero

        tst zra, $0x40
        orrne zra, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSWPB:  @0xCB30
        eor zrf, zrf            @ reset all flags

        lsr lr, zbc, $0x18
        orr lr, lr, lsl $0x08

        ands lr, $0x00000FF0
        orreq zrf, $flZ         @ set zero

        bic zbc, $0xFF000000
        orr zbc, lr, lsl $0x14

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSWPC:  @0xCB31
        eor zrf, zrf            @ reset all flags

        lsl lr, zbc, $0x08
        orr lr, lr, lsr $0x08

        ands lr, $0x0FF00000
        orreq zrf, $flZ         @ set zero

        bic zbc, $0x00FF0000
        orr zbc, lr, lsr $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSWPD:  @0xCB32
        eor zrf, zrf            @ reset all flags

        lsr lr, zde, $0x18
        orr lr, lr, lsl $0x08

        ands lr, $0x00000FF0
        orreq zrf, $flZ         @ set zero

        bic zde, $0xFF000000
        orr zde, lr, lsl $0x14

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSWPE:  @0xCB33
        eor zrf, zrf            @ reset all flags

        lsl lr, zde, $0x08
        orr lr, lr, lsr $0x08

        ands lr, $0x0FF00000
        orreq zrf, $flZ         @ set zero

        bic zde, $0x00FF0000
        orr zde, lr, lsr $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSWPH:  @0xCB34
        eor zrf, zrf            @ reset all flags

        lsr lr, zhl, $0x18
        orr lr, lr, lsl $0x08

        ands lr, $0x00000FF0
        orreq zrf, $flZ         @ set zero

        bic zhl, $0xFF000000
        orr zhl, lr, lsl $0x14

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSWPL:  @0xCB35
        eor zrf, zrf            @ reset all flags

        lsl lr, zhl, $0x08
        orr lr, lr, lsr $0x08

        ands lr, $0x0FF00000
        orreq zrf, $flZ         @ set zero

        bic zhl, $0x00FF0000
        orr zhl, lr, lsr $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSWPHL: @0xCB36
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        add zil, $1
        bl cpu_inst_b

        eor zrf, zrf            @ reset all flags

        lsl r0, $0x04
        orr r0, r0, lsr $0x08

        ands r0, $0xFF
        orreq zrf, $flZ         @ set zero

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSWPA:  @0xCB37
        eor zrf, zrf            @ reset all flags

        lsl zra, $0x04
        orr zra, zra, lsr $0x08

        ands zra, $0xFF
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRLB:  @0xCB38
        eor zrf, zrf            @ reset all flags

        lsrs lr, zbc, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0xFF000000
        orr zbc, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRLC:  @0xCB39
        eor zrf, zrf            @ reset all flags

        lsl lr, zbc, $0x08
        lsrs lr, $0x19          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zbc, $0x00FF0000
        orr zbc, lr, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRLD:  @0xCB3A
        eor zrf, zrf            @ reset all flags

        lsrs lr, zde, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zde, $0xFF000000
        orr zde, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRLE:  @0xCB3B
        eor zrf, zrf            @ reset all flags

        lsl lr, zde, $0x08
        lsrs lr, $0x19          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zde, $0x00FF0000
        orr zde, lr, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRLH:  @0xCB3C
        eor zrf, zrf            @ reset all flags

        lsrs lr, zhl, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0xFF000000
        orr zhl, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRLL:  @0xCB3D
        eor zrf, zrf            @ reset all flags

        lsl lr, zhl, $0x08
        lsrs lr, $0x19          @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0x00FF0000
        orr zhl, lr, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRLHL: @0xCB3E
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        add zil, $1
        bl cpu_inst_b

        eor zrf, zrf            @ reset all flags

        tst r0, $0x01           @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs r0, $1
        orreq zrf, $flZ         @ set zero

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbSRLA:  @0xCB3F
        eor zrf, zrf            @ reset all flags

        tst zra, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zra, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT0B:  @0xCB40
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x01000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT0C:  @0xCB41
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x00010000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT0D:  @0xCB42
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x01000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT0E:  @0xCB43
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x00010000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT0H:  @0xCB44
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x01000000

        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT0L:  @0xCB45
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00010000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT0HL: @0xCB46
        lsr r0, zhl, $0x10

        add zil, $1
        bl cpu_inst_b

        bl mmu_rb

        bic zrf, $flN
        orr zrf, $flH

        tst r0, $0x01
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT0A:  @0xCB47
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x01
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT1B:  @0xCB48
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x02000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT1C:  @0xCB49
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x00020000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT1D:  @0xCB4A
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x02000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT1E:  @0xCB4B
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x00020000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT1H:  @0xCB4C
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x02000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT1L:  @0xCB4D
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00020000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT1HL: @0xCB4E
        lsr r0, zhl, $0x10

        add zil, $1
        bl cpu_inst_b

        bl mmu_rb

        bic zrf, $flN
        orr zrf, $flH

        tst r0, $0x02
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT1A:  @0xCB4F
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x02
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT2B:  @0xCB50
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x04000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT2C:  @0xCB51
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x00040000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT2D:  @0xCB52
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x04000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT2E:  @0xCB53
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x00040000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT2H:  @0xCB54
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x04000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT2L:  @0xCB55
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00040000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT2HL: @0xCB56
        lsr r0, zhl, $0x10

        add zil, $1
        bl cpu_inst_b

        bl mmu_rb

        bic zrf, $flN
        orr zrf, $flH

        tst r0, $0x04
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT2A:  @0xCB57
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x04
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT3B:  @0xCB58
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x08000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT3C:  @0xCB59
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x00080000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT3D:  @0xCB5A
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x08000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT3E:  @0xCB5B
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x00080000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT3H:  @0xCB5C
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x08000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT3L:  @0xCB5D
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00080000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT3HL: @0xCB5E
        lsr r0, zhl, $0x10

        add zil, $1
        bl cpu_inst_b

        bl mmu_rb

        bic zrf, $flN
        orr zrf, $flH

        tst r0, $0x08
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT3A:  @0xCB5F
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x08
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT4B:  @0xCB60
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x10000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT4C:  @0xCB61
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x00100000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT4D:  @0xCB62
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x10000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT4E:  @0xCB63
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x00100000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT4H:  @0xCB64
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x10000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT4L:  @0xCB65
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00100000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT4HL: @0xCB66
        lsr r0, zhl, $0x10

        add zil, $1
        bl cpu_inst_b

        bl mmu_rb

        bic zrf, $flN
        orr zrf, $flH

        tst r0, $0x10
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT4A:  @0xCB67
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x10
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT5B:  @0xCB68
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x20000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT5C:  @0xCB69
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x00200000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT5D:  @0xCB6A
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x20000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT5E:  @0xCB6B
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x00200000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT5H:  @0xCB6C
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x20000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT5L:  @0xCB6D
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00200000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT5HL: @0xCB6E
        lsr r0, zhl, $0x10

        add zil, $1
        bl cpu_inst_b

        bl mmu_rb

        bic zrf, $flN
        orr zrf, $flH

        tst r0, $0x20
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT5A:  @0xCB6F
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x20
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT6B:  @0xCB70
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x40000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT6C:  @0xCB71
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x00400000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT6D:  @0xCB72
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x40000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT6E:  @0xCB73
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x00400000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT6H:  @0xCB74
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x40000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT6L:  @0xCB75
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00400000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT6HL: @0xCB76
        lsr r0, zhl, $0x10

        add zil, $1
        bl cpu_inst_b

        bl mmu_rb

        bic zrf, $flN
        orr zrf, $flH

        tst r0, $0x40
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT6A:  @0xCB77
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x40
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT7B:  @0xCB78
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x80000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT7C:  @0xCB79
        bic zrf, $flN
        orr zrf, $flH

        tst zbc, $0x00800000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT7D:  @0xCB7A
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x80000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT7E:  @0xCB7B
        bic zrf, $flN
        orr zrf, $flH

        tst zde, $0x00800000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT7H:  @0xCB7C
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x80000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT7L:  @0xCB7D
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00800000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT7HL: @0xCB7E
        lsr r0, zhl, $0x10

        add zil, $1
        bl cpu_inst_b

        bl mmu_rb

        bic zrf, $flN
        orr zrf, $flH

        tst r0, $0x80
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbBT7A:  @0xCB7F
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x80
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS0B:  @0xCB80
        bic zbc, $0x01000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS0C:  @0xCB81
        bic zbc, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS0D:  @0xCB82
        bic zde, $0x01000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS0E:  @0xCB83
        bic zde, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS0H:  @0xCB84
        bic zhl, $0x01000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS0L:  @0xCB85
        bic zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS0HL: @0xCB86
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        bic r0, $0x01

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS0A:  @0xCB87
        bic zra, $0x01

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS1B:  @0xCB88
        bic zbc, $0x02000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS1C:  @0xCB89
        bic zbc, $0x00020000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS1D:  @0xCB8A
        bic zde, $0x02000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS1E:  @0xCB8B
        bic zde, $0x00020000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS1H:  @0xCB8C
        bic zhl, $0x02000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS1L:  @0xCB8D
        bic zhl, $0x00020000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS1HL: @0xCB8E
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        bic r0, $0x02

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS1A:  @0xCB8F
        bic zra, $0x02

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS2B:  @0xCB90
        bic zbc, $0x04000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS2C:  @0xCB91
        bic zbc, $0x00040000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS2D:  @0xCB92
        bic zde, $0x04000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS2E:  @0xCB93
        bic zde, $0x00040000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS2H:  @0xCB94
        bic zhl, $0x04000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS2L:  @0xCB95
        bic zhl, $0x00040000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS2HL: @0xCB96
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        bic r0, $0x04

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS2A:  @0xCB97
        bic zra, $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS3B:  @0xCB98
        bic zbc, $0x08000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS3C:  @0xCB99
        bic zbc, $0x00080000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS3D:  @0xCB9A
        bic zde, $0x08000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS3E:  @0xCB9B
        bic zde, $0x00080000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS3H:  @0xCB9C
        bic zhl, $0x08000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS3L:  @0xCB9D
        bic zhl, $0x00080000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS3HL: @0xCB9E
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        bic r0, $0x08

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS3A:  @0xCB9F
        bic zra, $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS4B:  @0xCBA0
        bic zbc, $0x10000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS4C:  @0xCBA1
        bic zbc, $0x00100000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS4D:  @0xCBA2
        bic zde, $0x10000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS4E:  @0xCBA3
        bic zde, $0x00100000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS4H:  @0xCBA4
        bic zhl, $0x10000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS4L:  @0xCBA5
        bic zhl, $0x00100000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS4HL: @0xCBA6
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        bic r0, $0x10

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS4A:  @0xCBA7
        bic zra, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS5B:  @0xCBA8
        bic zbc, $0x20000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS5C:  @0xCBA9
        bic zbc, $0x00200000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS5D:  @0xCBAA
        bic zde, $0x20000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS5E:  @0xCBAB
        bic zde, $0x00200000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS5H:  @0xCBAC
        bic zhl, $0x20000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS5L:  @0xCBAD
        bic zhl, $0x00200000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS5HL: @0xCBAE
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        bic r0, $0x20

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS5A:  @0xCBAF
        bic zra, $0x20

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS6B:  @0xCBB0
        bic zbc, $0x40000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS6C:  @0xCBB1
        bic zbc, $0x00400000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS6D:  @0xCBB2
        bic zde, $0x40000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS6E:  @0xCBB3
        bic zde, $0x00400000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS6H:  @0xCBB4
        bic zhl, $0x40000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS6L:  @0xCBB5
        bic zhl, $0x00400000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS6HL: @0xCBB6
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        bic r0, $0x40

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS6A:  @0xCBB7
        bic zra, $0x40

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS7B:  @0xCBB8
        bic zbc, $0x80000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS7C:  @0xCBB9
        bic zbc, $0x00800000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS7D:  @0xCBBA
        bic zde, $0x80000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS7E:  @0xCBBB
        bic zde, $0x00800000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS7H:  @0xCBBC
        bic zhl, $0x80000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS7L:  @0xCBBD
        bic zhl, $0x00800000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS7HL: @0xCBBE
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        bic r0, $0x80

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbRS7A:  @0xCBBF
        bic zra, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST0B:  @0xCBC0
        orr zbc, $0x01000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST0C:  @0xCBC1
        orr zbc, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST0D:  @0xCBC2
        orr zde, $0x01000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST0E:  @0xCBC3
        orr zde, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST0H:  @0xCBC4
        orr zhl, $0x01000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST0L:  @0xCBC5
        orr zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST0HL: @0xCBC6
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        orr r0, $0x01

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST0A:  @0xCBC7
        orr zra, $0x01

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST1B:  @0xCBC8
        orr zbc, $0x02000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST1C:  @0xCBC9
        orr zbc, $0x00020000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST1D:  @0xCBCA
        orr zde, $0x02000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST1E:  @0xCBCB
        orr zde, $0x00020000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST1H:  @0xCBCC
        orr zhl, $0x02000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST1L:  @0xCBCD
        orr zhl, $0x00020000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST1HL: @0xCBCE
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        orr r0, $0x02

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST1A:  @0xCBCF
        orr zra, $0x02

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST2B:  @0xCBD0
        orr zbc, $0x04000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST2C:  @0xCBD1
        orr zbc, $0x00040000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST2D:  @0xCBD2
        orr zde, $0x04000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST2E:  @0xCBD3
        orr zde, $0x00040000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST2H:  @0xCBD4
        orr zhl, $0x04000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST2L:  @0xCBD5
        orr zhl, $0x00040000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST2HL: @0xCBD6
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        orr r0, $0x04

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST2A:  @0xCBD7
        orr zra, $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST3B:  @0xCBD8
        orr zbc, $0x08000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST3C:  @0xCBD9
        orr zbc, $0x00080000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST3D:  @0xCBDA
        orr zde, $0x08000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST3E:  @0xCBDB
        orr zde, $0x00080000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST3H:  @0xCBDC
        orr zhl, $0x08000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST3L:  @0xCBDD
        orr zhl, $0x00080000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST3HL: @0xCBDE
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        orr r0, $0x08

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST3A:  @0xCBDF
        orr zra, $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST4B:  @0xCBE0
        orr zbc, $0x10000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST4C:  @0xCBE1
        orr zbc, $0x00100000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST4D:  @0xCBE2
        orr zde, $0x10000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST4E:  @0xCBE3
        orr zde, $0x00100000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST4H:  @0xCBE4
        orr zhl, $0x10000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST4L:  @0xCBE5
        orr zhl, $0x00100000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST4HL: @0xCBE6
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        orr r0, $0x10

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST4A:  @0xCBE7
        orr zra, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST5B:  @0xCBE8
        orr zbc, $0x20000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST5C:  @0xCBE9
        orr zbc, $0x00200000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST5D:  @0xCBEA
        orr zde, $0x20000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST5E:  @0xCBEB
        orr zde, $0x00200000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST5H:  @0xCBEC
        orr zhl, $0x20000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST5L:  @0xCBED
        orr zhl, $0x00200000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST5HL: @0xCBEE
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        orr r0, $0x20

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST5A:  @0xCBEF
        orr zra, $0x20

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST6B:  @0xCBF0
        orr zbc, $0x40000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST6C:  @0xCBF1
        orr zbc, $0x00400000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST6D:  @0xCBF2
        orr zde, $0x40000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST6E:  @0xCBF3
        orr zde, $0x00400000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST6H:  @0xCBF4
        orr zhl, $0x40000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST6L:  @0xCBF5
        orr zhl, $0x00400000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST6HL: @0xCBF6
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        orr r0, $0x40

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST6A:  @0xCBF7
        orr zra, $0x40

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST7B:  @0xCBF8
        orr zbc, $0x80000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST7C:  @0xCBF9
        orr zbc, $0x00800000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST7D:  @0xCBFA
        orr zde, $0x80000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST7E:  @0xCBFB
        orr zde, $0x00800000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST7H:  @0xCBFC
        orr zhl, $0x80000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST7L:  @0xCBFD
        orr zhl, $0x00800000

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST7HL: @0xCBFE
        add zil, $1
        bl cpu_inst_b

        lsr r0, zhl, $0x10
        bl mmu_rb

        orr r0, $0x80

        add zil, $1
        bl cpu_inst_b

        orr r0, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

cbST7A:  @0xCBFF
        orr zra, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_ret

        .end
