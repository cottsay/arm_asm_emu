/******************************************************************************
 * \file cpu.S
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

cpu_inst_r:
        b cpu_ret

cpu_step_cont:
        bic zil, $0x00800000
        ldr r1, =stash
        ldmfd r1, {r0, pc}

cpu_inst_b:
        orr zil, $0x00800000
        ldr r1, =stash
        stmea r1, {r0, lr}
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
        b cpu_inst_r

opLDBCnn:@0x01
        bl mmu_rih1
        and zrc, r0, $0xFF
        lsr zrb, r0, $0x08

        add zil, $3
        add zpc, $0x00030000
        b cpu_inst_r

opLDBCA: @0x02
        orr r0, zrc, zrb, lsl $0x08
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opIBC:   @0x03
        orr r0, zrc, zrb, lsl $0x08

        add r0, $1

        and zrc, r0, $0xFF
        lsr zrb, r0, $0x08
        and zrb, $0xFF                  @ clear any carried bit(s)

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opIB:    @0x04
        bic zrf, $flN           @ reset subtract

        add r0, zrb, $1

        eor r1, r0, zrb
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        biceq zrf, $flH                 @ reset half-carry

        ands zrb, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opDB:    @0x05
        orr zrf, $flN           @ set subtract

        add r0, zrb, $0xFF      @ subtract 1

        eor r1, zrb, r0
        eor r1, r1, $0xFF       @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        bicne zrf, $flH                 @ reset half-carry
        orreq zrf, $flH                 @ set half-carry

        ands zrb, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDBn:  @0x06
        bl mmu_ri1

        mov zrb, r0

        add zil, $2
        add zpc, $0x00020000
        b cpu_inst_r

opRLCA:  @0x07
        eor zrf, zrf            @ reset all flags

        lsl zra, $0x01
        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry
        orrne zra, $0x01                @ set bit 0
        andne zra, $0xFF        @ clear any carried bit(s)

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDnnSP:@0x08
        bl mmu_rih1
        lsl r0, $0x10
        orr r0, zsp, lsr $0x10
        bl mmu_wh

        add zil, $5
        add zpc, $0x00030000
        b cpu_inst_r

opAHLBC: @0x09
        bic zrf, $flN           @ reset subtract

        lsr r0, zhl, $0x10              @ put HL in r0
        orr r1, zrc, zrb, lsl $0x08     @ put BC in r1
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
        b cpu_inst_r

opLDABC: @0x0A
        orr r0, zrc, zrb, lsl $0x08
        bl mmu_rb

        mov zra, r0

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opDBC:   @0x0B
        orr r0, zrc, zrb, lsl $0x08

        sub r0, $1

        and zrc, r0, $0xFF
        lsr zrb, r0, $0x08
        and zrb, $0xFF                  @ clear any carried bit(s)

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opIC:    @0x0C
        bic zrf, $flN           @ reset subtract

        add r0, zrc, $1

        eor r1, r0, zrc
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        biceq zrf, $flH                 @ reset half-carry

        ands zrc, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opDC:    @0x0D
        orr zrf, $flN           @ set subtract

        add r0, zrc, $0xFF      @ subtract 1

        eor r1, zrc, r0
        eor r1, r1, $0xFF       @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        bicne zrf, $flH                 @ reset half-carry
        orreq zrf, $flH                 @ set half-carry

        ands zrc, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDCn:  @0x0E
        bl mmu_ri1

        mov zrc, r0
        add zil, $2
        add zpc, $0x00020000
        b cpu_inst_r

opRRCA:  @0x0F
        eor zrf, zrf            @ reset all flags

        tst zra, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry
        orrne zra, $0x100               @ set bit 8

        lsr zra, $0x01

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opSTOP:  @0x10
        orr zil, $0x01000000

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDDEnn:@0x11
        bl mmu_rih1
        and zre, r0, $0xFF
        lsr zrd, r0, $0x08

        add zil, $3
        add zpc, $0x00030000
        b cpu_inst_r

opLDDEA: @0x12
        orr r0, zre, zrd, lsl $0x08
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opIDE:   @0x13
        orr r0, zre, zrd, lsl $0x08

        add r0, $1

        and zre, r0, $0xFF
        lsr zrd, r0, $0x08
        and zrd, $0xFF                  @ clear any carried bit(s)

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opID:    @0x14
        bic zrf, $flN           @ reset subtract

        add r0, zrd, $1

        eor r1, r0, zrd
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        biceq zrf, $flH                 @ reset half-carry

        ands zrd, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opDD:    @0x15
        orr zrf, $flN           @ set subtract

        add r0, zrd, $0xFF      @ subtract 1

        eor r1, zrd, r0
        eor r1, r1, $0xFF       @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        bicne zrf, $flH                 @ reset half-carry
        orreq zrf, $flH                 @ set half-carry

        ands zrd, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDDn:  @0x16
        bl mmu_ri1

        mov zrd, r0

        add zil, $2
        add zpc, $0x00020000
        b cpu_inst_r

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
        b cpu_inst_r

opJRn:   @0x18
        bl mmu_ri1
        lsl r0, $0x18
        add zpc, r0, asr $0x08

        add zil, $3
        add zpc, $0x00020000
        b cpu_inst_r

opAHLDE: @0x19
        bic zrf, $flN           @ reset subtract

        lsr r0, zhl, $0x10              @ put HL in r0
        orr r1, zre, zrd, lsl $0x08     @ put DE in r1
        add lr, r0, r1

        eor r1, r1, r0
        eor r1, r1, lr          @ XOR all three
        tst r1, $0x1000         @ if bit 12 is set
        orrne zrf, $flH                 @ set half-carry
        biceq zrf, $flH                 @ reset half-carry

        tst r1, $0x10000        @ if bit 16 is set
        orrne zrf, $flC                 @ set full-carry
        biceq zrf, $flC                 @ reset full-carry

        lsl zhl, lr, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDADE: @0x1A
        orr r0, zre, zrd, lsl $0x08
        bl mmu_rb

        mov zra, r0

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opDDE:   @0x1B
        orr r0, zre, zrd, lsl $0x08

        sub r0, $1

        and zre, r0, $0xFF
        lsr zrd, r0, $0x08
        and zrd, $0xFF                  @ clear any carried bit(s)

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opIE:    @0x1C
        bic zrf, $flN           @ reset subtract

        add r0, zre, $1

        eor r1, r0, zre
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        biceq zrf, $flH                 @ reset half-carry

        ands zre, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opDE:    @0x1D
        orr zrf, $flN           @ set subtract

        add r0, zre, $0xFF      @ subtract 1

        eor r1, zre, r0
        eor r1, r1, $0xFF       @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        bicne zrf, $flH                 @ reset half-carry
        orreq zrf, $flH                 @ set half-carry

        ands zre, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDEn:  @0x1E
        bl mmu_ri1

        mov zre, r0

        add zil, $2
        add zpc, $0x00020000
        b cpu_inst_r

opRRA:   @0x1F
        tst zrf, $flC           @ if carry
        orrne zra, $0x100               @ set bit 8

        eor zrf, zrf            @ reset all flags

        tst zra, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsr zra, $0x01

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opJRNZn: @0x20
        add zil, $2

        tst zrf, $flZ
        addne zpc, $0x00020000
        bne cpu_inst_r

        add zil, $1

        bl mmu_ri1
        lsl r0, $0x18
        add zpc, r0, asr $0x08
        add zpc, $0x00020000

        b cpu_inst_r

opLDHLnn:@0x21
        bl mmu_rih1
        lsl zhl, r0, $0x10

        add zil, $3
        add zpc, $0x00030000
        b cpu_inst_r

opLDHLiA:@0x22
        orr r0, zra, zhl
        bl mmu_wb

        add zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opIHL:   @0x23
        add zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opIH:    @0x24
        bic zrf, $flZNH         @ reset zero, subtract and half-carry

        add zhl, $0x01000000
        tst zhl, $0x0F000000    @ if lower nibble is zero
        orreq zrf, $flH                 @ set half-carry
        tst zhl, $0xFF000000    @ if result is completely zero
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opDH:    @0x25
        orr zrf, $flZNH         @ set zero, subtract and half-carry

        tst zhl, $0x0F000000    @ if lower nibble is not completely zero
        bicne zrf, $flH                 @ reset half-carry
        add zhl, $0xFF000000
        tst zhl, $0xFF000000    @ if result is not completely zero
        bicne zrf, $flZ                 @ reset zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDHn:  @0x26
        bl mmu_ri1

        bic zhl, $0xFF000000
        orr zhl, r0, lsl $0x18

        add zil, $2
        add zpc, $0x00020000
        b cpu_inst_r

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
        b cpu_inst_r

opJRZn:  @0x28
        add zil, $2

        tst zrf, $flZ
        addeq zpc, $0x00020000
        beq cpu_inst_r

        add zil, $1

        bl mmu_ri1
        lsl r0, $0x18
        add zpc, r0, asr $0x08
        add zpc, $0x00020000

        b cpu_inst_r

opAHLHL: @0x29
        bic zrf, $flNHC         @ reset subtract, half-carry and full-carry

        tst zhl, $0x08000000    @ if bit 11 is set
        orrne zrf, $flH                 @ set half-carry

        adds zhl, zhl
        orrcs zrf, $flC                 @ set full-carry

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDAHLi:@0x2A
        lsr r0, zhl, $0x10
        bl mmu_rb
        mov zra, r0

        add zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opDHL:   @0x2B
        sub zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

opLDLn:  @0x2E
        bl mmu_ri1

        bic zhl, $0x00FF0000
        orr zhl, r0, lsl $0x10

        add zil, $2
        add zpc, $0x00020000
        b cpu_inst_r

opCPL:   @0x2F
        mvn zra, zra
        and zra, $0xFF
        orr zrf, $flNH

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opJRNCn: @0x30
        add zil, $2

        tst zrf, $flC
        addne zpc, $0x00020000
        bne cpu_inst_r

        add zil, $1

        bl mmu_ri1
        lsl r0, $0x18
        add zpc, r0, asr $0x08
        add zpc, $0x00020000

        b cpu_inst_r

opLDSPnn:@0x31
        bl mmu_rih1
        lsl zsp, r0, $0x10

        add zil, $3
        add zpc, $0x00030000
        b cpu_inst_r

opLDHLdA:@0x32
        orr r0, zra, zhl
        bl mmu_wb

        sub zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opISP:   @0x33
        add zsp, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

opSCF:   @0x37
        bic zrf, $flNH          @ reset subtract and half-carry
        orr zrf, $flC           @ set carry

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opJRCn: @0x38
        add zil, $2

        tst zrf, $flC
        addeq zpc, $0x00020000
        beq cpu_inst_r

        add zil, $1

        bl mmu_ri1
        lsl r0, $0x18
        add zpc, r0, asr $0x08
        add zpc, $0x00020000

        b cpu_inst_r

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
        b cpu_inst_r

opLDAHLd:@0x3A
        lsr r0, zhl, $0x10
        bl mmu_rb
        mov zra, r0

        sub zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opDSP:   @0x3B
        sub zsp, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

opLDAn:  @0x3E
        bl mmu_ri1

        mov zra, r0

        add zil, $2
        add zpc, $0x00020000
        b cpu_inst_r

opCCF:   @0x3F
        bic zrf, $flNH          @ reset subtract and half-carry
        eor zrf, $flC           @ complement carry

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDBB:  @0x40
        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDBC:  @0x41
        mov zrb, zrc

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDBD:  @0x42
        mov zrb, zrd

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDBE:  @0x43
        mov zrb, zre

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDBH:  @0x44
        lsr zrb, zhl, $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDBL:  @0x45
        lsr zrb, zhl, $0x10
        and zrb, $0x000000FF

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDBHL: @0x46
        lsr r0, zhl, $0x10
        bl mmu_rb

        mov zrb, r0

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDBA:  @0x47
        mov zrb, zra

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDCB:  @0x48
        mov zrc, zrb

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDCC:  @0x49
        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDCD:  @0x4A
        mov zrc, zrd

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDCE:  @0x4B
        mov zrc, zre

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDCH:  @0x4C
        lsr zrc, zhl, $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDCL:  @0x4D
        lsr zrc, zhl, $0x10
        and zrc, $0x000000FF

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDCHL: @0x4E
        lsr r0, zhl, $0x10
        bl mmu_rb

        mov zrc, r0

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDCA:  @0x4F
        mov zrc, zra

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDDB:  @0x50
        mov zrd, zrb

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDDC:  @0x51
        mov zrd, zrc

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDDD:  @0x52
        add zil, $1

        add zpc, $0x00010000
        b cpu_inst_r

opLDDE:  @0x53
        mov zrd, zre

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDDH:  @0x54
        lsr zrd, zhl, $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDDL:  @0x55
        lsr zrd, zhl, $0x10
        and zrd, $0x000000FF

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDDHL: @0x56
        lsr r0, zhl, $0x10
        bl mmu_rb

        mov zrd, r0

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDDA:  @0x57
        mov zrd, zra

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDEB:  @0x58
        mov zre, zrb

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDEC:  @0x59
        mov zre, zrc

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDED:  @0x5A
        mov zre, zrd

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDEE:  @0x5B
        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDEH:  @0x5C
        lsr zre, zhl, $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDEL:  @0x5D
        lsr zre, zhl, $0x10
        and zre, $0x000000FF

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDEHL: @0x5E
        lsr r0, zhl, $0x10
        bl mmu_rb

        mov zre, r0

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDEA:  @0x5F
        mov zre, zra

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDHB:  @0x60
        bic zhl, $0xFF000000
        orr zhl, zrb, lsl $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDHC:  @0x61
        bic zhl, $0xFF000000
        orr zhl, zrc, lsl $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDHD:  @0x62
        bic zhl, $0xFF000000
        orr zhl, zrd, lsl $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDHE:  @0x63
        bic zhl, $0xFF000000
        orr zhl, zre, lsl $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDHH:  @0x64
        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDHL:  @0x65
        bic zhl, $0xFF000000
        orr zhl, zhl, lsl $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDHHL: @0x66
        lsr r0, zhl, $0x10
        bl mmu_rb

        bic zhl, $0xFF000000
        orr zhl, r0, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDHA:  @0x67
        bic zhl, $0xFF000000
        orr zhl, zra, lsl $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDLB:  @0x68
        bic zhl, $0x00FF0000
        orr zhl, zrb, lsl $0x10

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDLC:  @0x69
        bic zhl, $0x00FF0000
        orr zhl, zrc, lsl $0x10

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDLD:  @0x6A
        bic zhl, $0x00FF0000
        orr zhl, zrd, lsl $0x10

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDLE:  @0x6B
        bic zhl, $0x00FF0000
        orr zhl, zre, lsl $0x10

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDLH:  @0x6C
        bic zhl, $0x00FF0000
        orr zhl, zhl, lsr $0x08

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDLL:  @0x6D
        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDLHL: @0x6E
        lsr r0, zhl, $0x10
        bl mmu_rb

        bic zhl, $0x00FF0000
        orr zhl, r0, lsl $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDLA:  @0x6F
        bic zhl, $0x00FF0000
        orr zhl, zra, lsl $0x10

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDHLB: @0x70
        orr r0, zrb, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDHLC: @0x71
        orr r0, zrc, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDHLD: @0x72
        orr r0, zrd, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDHLE: @0x73
        orr r0, zre, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDHLH: @0x74
        orr r0, zhl, zhl, lsr $0x18
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDHLL: @0x75
        orr r0, zhl, zhl, lsr $0x10
        bic r0, $0x0000FF00
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opHALT:  @0x76
        orr zil, $0x02000000

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDHLA: @0x77
        orr r0, zra, zhl
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDAB:  @0x78
        mov zra, zrb

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDAC:  @0x79
        mov zra, zrc

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDAD:  @0x7A
        mov zra, zrd

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDAE:  @0x7B
        mov zra, zre

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDAH:  @0x7C
        lsr zra, zhl, $0x18

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDAL:  @0x7D
        lsr zra, zhl, $0x10
        and zra, $0x000000FF

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opLDAHL: @0x7E
        lsr r0, zhl, $0x10
        bl mmu_rb

        mov zra, r0

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDAA:  @0x7F
        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opAAB:   @0x80
        eor zrf, zrf            @ reset all flags

        add r0, zra, zrb

        eor r1, r0, zra
        eor r1, r1, zrb         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opAAC:   @0x81
        eor zrf, zrf            @ reset all flags

        add r0, zra, zrc

        eor r1, r0, zra
        eor r1, r1, zrc         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opAAD:   @0x82
        eor zrf, zrf            @ reset all flags

        add r0, zra, zrd

        eor r1, r0, zra
        eor r1, r1, zrd         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opAAE:   @0x83
        eor zrf, zrf            @ reset all flags

        add r0, zra, zre

        eor r1, r0, zra
        eor r1, r1, zre         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

opAcAB:  @0x88
        tst zrf, $flC           @ handle possible carry
        moveq r0, zrb
        addne r0, zrb, $1

        eor zrf, zrf            @ reset all flags

        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zrb         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000

        b cpu_inst_r

opAcAC:  @0x89
        tst zrf, $flC
        moveq r0, zrc
        addne r0, zrc, $1

        eor zrf, zrf            @ reset all flags

        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zrc         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opAcAD:  @0x8A
        tst zrf, $flC
        moveq r0, zrd
        addne r0, zrd, $1

        eor zrf, zrf            @ reset all flags

        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zrd         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opAcAE:  @0x8B
        tst zrf, $flC
        moveq r0, zre
        addne r0, zre, $1

        eor zrf, zrf            @ reset all flags

        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zre         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

opSAB:   @0x90
        mov zrf, $flN           @ set only subtract

        mvn r1, zrb
        add r1, $1              @ 2's compliment
        add r0, zra, r1

        eor r1, r0, zra
        eor r1, r1, zrb         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opSAC:   @0x91
        mov zrf, $flN           @ set only subtract

        mvn r1, zrc
        add r1, $1              @ 2's compliment
        add r0, zra, r1

        eor r1, r0, zra
        eor r1, r1, zrc         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opSAD:   @0x92
        mov zrf, $flN           @ set only subtract

        mvn r1, zrd
        add r1, $1              @ 2's compliment
        add r0, zra, r1

        eor r1, r0, zra
        eor r1, r1, zrd         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opSAE:   @0x93
        mov zrf, $flN           @ set only subtract

        mvn r1, zre
        add r1, $1              @ 2's compliment
        add r0, zra, r1

        eor r1, r0, zra
        eor r1, r1, zre         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

opSAA:   @0x97
        mov zrf, $flN           @ set only subtract
        orr zrf, $flZ           @ set zero

        mov zra, $0

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opScAB:  @0x98
        mvn r1, zrb
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r0, zra, r1

        mov zrf, $flN           @ set only subtract

        eor r1, r0, zra
        eor r1, r1, zrb         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opScAC:  @0x99
        mvn r1, zrc
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r0, zra, r1

        mov zrf, $flN           @ set only subtract

        eor r1, r0, zra
        eor r1, r1, zrc         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opScAD:  @0x9A
        mvn r1, zrd
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r0, zra, r1

        mov zrf, $flN           @ set only subtract

        eor r1, r0, zra
        eor r1, r1, zrd         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opScAE:  @0x9B
        mvn r1, zre
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r0, zra, r1

        mov zrf, $flN           @ set only subtract

        eor r1, r0, zra
        eor r1, r1, zre         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands zra, r0, $0xFF             @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

opANAB:  @0xA0
        mov zrf, $flH           @ set only half-carry

        ands zra, zrb
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opANAC:  @0xA1
        mov zrf, $flH           @ set only half-carry

        ands zra, zrc
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opANAD:  @0xA2
        mov zrf, $flH           @ set only half-carry

        ands zra, zrd
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opANAE:  @0xA3
        mov zrf, $flH           @ set only half-carry

        ands zra, zre
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opANAH:  @0xA4
        mov zrf, $flH           @ set only half-carry

        ands zra, zhl, lsr $0x18
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opANAL:  @0xA5
        mov zrf, $flH           @ set only half-carry

        ands zra, zhl, lsr $0x10
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opANAHL: @0xA6
        lsr r0, zhl, $0x10
        bl mmu_rb

        mov zrf, $flH           @ set only half-carry

        ands zra, r0
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opANAA:  @0xA7
        mov zrf, $flH           @ set only half-carry

        ands zra, zra
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opXOAB:  @0xA8
        eor zrf, zrf            @ reset all flags

        eors zra, zrb
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opXOAC:  @0xA9
        eor zrf, zrf            @ reset all flags

        eors zra, zrc
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opXOAD:  @0xAA
        eor zrf, zrf            @ reset all flags

        eors zra, zrd
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opXOAE:  @0xAB
        eor zrf, zrf            @ reset all flags

        eors zra, zre
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opXOAH:  @0xAC
        eor zrf, zrf            @ reset all flags

        eors zra, zhl, lsr $0x18
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opXOAL:  @0xAD
        eor zrf, zrf            @ reset all flags

        eor zra, zhl, lsr $0x10
        bics zra, $0x0000FF00
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opXOAHL: @0xAE
        lsr r0, zhl, $0x10
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        eors zra, r0
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opXOAA:  @0xAF
        eor zrf, zrf            @ reset all flags

        eors zra, zra
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opORAB:  @0xB0
        eor zrf, zrf            @ reset all flags

        orrs zra, zrb
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opORAC:  @0xB1
        eor zrf, zrf            @ reset all flags

        orrs zra, zrc
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opORAD:  @0xB2
        eor zrf, zrf            @ reset all flags

        orrs zra, zrd
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opORAE:  @0xB3
        eor zrf, zrf            @ reset all flags

        orrs zra, zre
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opORAH:  @0xB4
        eor zrf, zrf            @ reset all flags

        orrs zra, zhl, lsr $0x18
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opORAL:  @0xB5
        eor zrf, zrf            @ reset all flags

        orr zra, zhl, lsr $0x10
        bics zra, $0x0000FF00
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opORAHL: @0xB6
        lsr r0, zhl, $0x10
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        orrs zra, r0
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opORAA:  @0xB7
        eor zrf, zrf            @ reset all flags

        orrs zra, zra
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opCAB:   @0xB8
        mov zrf, $flN           @ set only subtract

        mvn r0, zrb
        add r0, $1              @ 2's compliment
        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zrb         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opCAC:   @0xB9
        mov zrf, $flN           @ set only subtract

        mvn r0, zrc
        add r0, $1              @ 2's compliment
        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zrc         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opCAD:   @0xBA
        mov zrf, $flN           @ set only subtract

        mvn r0, zrd
        add r0, $1              @ 2's compliment
        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zrd         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear the carried bit
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opCAE:   @0xBB
        mov zrf, $flN           @ set only subtract

        mvn r0, zre
        add r0, $1              @ 2's compliment
        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zre         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

opCAA:   @0xBF
        mov zrf, $flN           @ set only subtract
        orr zrf, $flZ           @ set zero

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opRETNZ: @0xC0
        add zil, $2

        tst zrf, $flZ
        addne zpc, $0x00010000
        bne cpu_inst_r

        add zil, $3

        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsl zpc, r0, $0x10

        b cpu_inst_r

opPOPBC: @0xC1
        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsr zrb, r0, $0x08
        and zrc, r0, $0xFF

        add zil, $3
        add zpc, $0x00010000
        b cpu_inst_r

opJPNZnn:@0xC2
        add zil, $3

        tst zrf, $flZ
        addne zpc, $0x00030000
        bne cpu_inst_r

        add zil, $1

        bl mmu_rih1
        lsl zpc, r0, $0x10
        b cpu_inst_r

opJPnn:  @0xC3
        bl mmu_rih1
        lsl zpc, r0, $0x10

        add zil, $4
        b cpu_inst_r

opCNZnn: @0xC4
        add zil, $3

        tst zrf, $flZ
        addne zpc, $0x00030000
        bne cpu_inst_r

        add zil, $3

        bl mmu_rih1

        add r1, zpc, $0x00030000
        lsl zpc, r0, $0x10

        sub zsp, $0x00020000

        orr r0, zsp, r1, lsr $0x10
        bl mmu_wh

        b cpu_inst_r

opPUSBC: @0xC5
        sub zsp, $0x00020000
        orr r0, zrc, zrb, lsl $0x08
        orr r0, zsp
        bl mmu_wh

        add zil, $4
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

opR00H:  @0xC7
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00000000
        b cpu_inst_r

opRETZ:  @0xC8
        add zil, $2

        tst zrf, $flZ
        addeq zpc, $0x00010000
        beq cpu_inst_r

        add zil, $3

        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsl zpc, r0, $0x10

        b cpu_inst_r

opRET:   @0xC9
        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsl zpc, r0, $0x10

        add zil, $4
        b cpu_inst_r

opJPZnn: @0xCA
        add zil, $3

        tst zrf, $flZ
        addeq zpc, $0x00030000
        beq cpu_inst_r

        add zil, $1

        bl mmu_rih1
        lsl zpc, r0, $0x10
        b cpu_inst_r

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
        beq cpu_inst_r

        add zil, $3

        bl mmu_rih1

        add r1, zpc, $0x00030000
        lsl zpc, r0, $0x10

        sub zsp, $0x00020000
        orr r0, zsp, r1, lsr $0x10
        bl mmu_wh

        b cpu_inst_r

opCnn:   @0xCD
        bl mmu_rih1

        add r1, zpc, $0x00030000
        lsl zpc, r0, $0x10

        sub zsp, $0x00020000
        orr r0, zsp, r1, lsr $0x10
        bl mmu_wh

        add zil, $6
        b cpu_inst_r

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
        b cpu_inst_r

opR08H:  @0xCF
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00080000
        b cpu_inst_r

opRETNC: @0xD0
        add zil, $2

        tst zrf, $flC
        addne zpc, $0x00010000
        bne cpu_inst_r

        add zil, $3

        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsl zpc, r0, $0x10

        b cpu_inst_r

opPOPDE: @0xD1
        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsr zrd, r0, $0x08
        and zre, r0, $0xFF

        add zil, $3
        add zpc, $0x00010000
        b cpu_inst_r

opJPNCnn:@0xD2
        add zil, $3

        tst zrf, $flC
        addne zpc, $0x00030000
        bne cpu_inst_r

        add zil, $1

        bl mmu_rih1
        lsl zpc, r0, $0x10
        b cpu_inst_r

opCNCnn: @0xD4
        add zil, $3

        tst zrf, $flC
        addne zpc, $0x00030000
        bne cpu_inst_r

        add zil, $3

        bl mmu_rih1

        add r1, zpc, $0x00030000
        lsl zpc, r0, $0x10

        sub zsp, $0x00020000
        orr r0, zsp, r1, lsr $0x10
        bl mmu_wh

        b cpu_inst_r

opPUSDE: @0xD5
        sub zsp, $0x00020000
        orr r0, zre, zrd, lsl $0x08
        orr r0, zsp
        bl mmu_wh

        add zil, $4
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

opR10H:  @0xD7
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00100000
        b cpu_inst_r

opRETC:  @0xD8
        add zil, $2

        tst zrf, $flC
        addeq zpc, $0x00010000
        beq cpu_inst_r

        add zil, $3

        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsl zpc, r0, $0x10

        b cpu_inst_r

opRETI:  @0xD9
        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsl zpc, r0, $0x10

        orr zil, $(intE << intO)

        add zil, $4
        b cpu_inst_r

opJPCnn: @0xDA
        add zil, $3

        tst zrf, $flC
        addeq zpc, $0x00030000
        beq cpu_inst_r

        add zil, $1

        bl mmu_rih1
        lsl zpc, r0, $0x10
        b cpu_inst_r

opCCnn:  @0xDC
        add zil, $3

        tst zrf, $flC
        addeq zpc, $0x00030000
        beq cpu_inst_r

        add zil, $3

        bl mmu_rih1

        add r1, zpc, $0x00030000
        lsl zpc, r0, $0x10

        sub zsp, $0x00020000
        orr r0, zsp, r1, lsr $0x10
        bl mmu_wh

        b cpu_inst_r

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
        b cpu_inst_r

opR18H:  @0xDF
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00180000
        b cpu_inst_r

opLDFnA: @0xE0
        add zil, $1
        bl cpu_inst_b

        bl mmu_ri1
        orr r0, $0xFF00
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        add zil, $2
        add zpc, $0x00020000
        b cpu_inst_r

opPOPHL: @0xE1
        lsr r0, zsp, $0x10
        add zsp, $0x00020000
        bl mmu_rh

        lsl zhl, r0, $0x10

        add zil, $3
        add zpc, $0x00010000
        b cpu_inst_r

opLDFCA: @0xE2
        orr r0, zrc, $0xFF00
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opPUSHL: @0xE5
        sub zsp, $0x00020000
        orr r0, zsp, zhl, lsr $0x10
        bl mmu_wh

        add zil, $4
        add zpc, $0x00010000
        b cpu_inst_r

opANAn:  @0xE6
        bl mmu_ri1

        mov zrf, $flH           @ set only half-carry

        ands zra, r0
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00020000
        b cpu_inst_r

opR20H:  @0xE7
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00200000
        b cpu_inst_r

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
        b cpu_inst_r

opJPHL:  @0xE9
        mov zpc, zhl

        add zil, $1
        b cpu_inst_r

opLDnnA: @0xEA
        add zil, $2
        bl cpu_inst_b

        bl mmu_rih1
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        add zil, $2
        add zpc, $0x00030000
        b cpu_inst_r

opXOAn:  @0xEE
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        eors zra, r0
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00020000
        b cpu_inst_r

opR28H:  @0xEF
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00280000
        b cpu_inst_r

opLDAFn: @0xF0
        add zil, $1
        bl cpu_inst_b

        bl mmu_ri1
        orr r0, $0xFF00
        bl mmu_rb

        mov zra, r0

        add zil, $2
        add zpc, $0x00020000
        b cpu_inst_r

opPOPAF: @0xF1
        lsr r0, zsp, $0x10
        bl mmu_rh

        add zsp, $0x00020000

        lsr zra, r0, $0x08
        and zrf, r0, $flM

        add zil, $3
        add zpc, $0x00010000
        b cpu_inst_r

opLDAFC: @0xF2
        orr r0, zrc, $0xFF00
        bl mmu_rb

        mov zra, r0

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opDI:    @0xF3
        bic zil, $(intE << intO)        @ Disable interrupts

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

opPUSAF: @0xF5
        sub zsp, $0x00020000
        orr r0, zrf, zra, lsl $0x08
        orr r0, zsp
        bl mmu_wh

        add zil, $4
        add zpc, $0x00010000
        b cpu_inst_r

opORAn:  @0xF6
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        orrs zra, r0
        orreq zrf, $flZ                 @ set zero

        add zil, $2
        add zpc, $0x00020000
        b cpu_inst_r

opR30H:  @0xF7
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00300000
        b cpu_inst_r

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
        b cpu_inst_r

opLDSHL: @0xF9
        mov zsp, zhl

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

opLDAnn: @0xFA
        add zil, $2
        bl cpu_inst_b

        bl mmu_rih1
        bl mmu_rb

        mov zra, r0

        add zil, $2
        add zpc, $0x00030000
        b cpu_inst_r

opEI:    @0xFB
        orr zil, $(intE << intO)        @ Enable interrupts

        add zil, $1
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

opR38H:  @0xFF
        add zpc, $0x00010000
        sub zsp, $0x00020000
        orr r0, zsp, zpc, lsr $0x10
        bl mmu_wh

        add zil, $4
        mov zpc, $0x00380000
        b cpu_inst_r

/* CB-PREFIX INSTRUCTIONS */

cbRLCB:  @0xCB00
        eor zrf, zrf            @ reset all flags

        lsl zrb, $1
        tst zrb, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry
        orrne zrb, $0x01                @ set bit 0

        ands zrb, $0xFF         @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRLCC:  @0xCB01
        eor zrf, zrf            @ reset all flags

        lsl zrc, $1
        tst zrc, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry
        orrne zrc, $0x01                @ set bit 0

        ands zrc, $0xFF         @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRLCD:  @0xCB02
        eor zrf, zrf            @ reset all flags

        lsl zrd, $1
        tst zrd, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry
        orrne zrd, $0x01                @ set bit 0

        ands zrd, $0xFF         @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRLCE:  @0xCB03
        eor zrf, zrf            @ reset all flags

        lsl zre, $1
        tst zre, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry
        orrne zre, $0x01                @ set bit 0

        ands zre, $0xFF         @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

cbRRCB:  @0xCB08
        eor zrf, zrf            @ reset all flags

        tst zrb, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry
        orrne zrb, $0x100               @ set bit 8

        lsrs zrb, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRRCC:  @0xCB09
        eor zrf, zrf            @ reset all flags

        tst zrc, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry
        orrne zrc, $0x100               @ set bit 8

        lsrs zrc, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRRCD:  @0xCB0A
        eor zrf, zrf            @ reset all flags

        tst zrd, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry
        orrne zrd, $0x100               @ set bit 8

        lsrs zrd, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRRCE:  @0xCB0B
        eor zrf, zrf            @ reset all flags

        tst zre, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry
        orrne zre, $0x100               @ set bit 8

        lsrs zre, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

cbRRCA:  @0xCB0F
        eor zrf, zrf            @ reset all flags

        tst zra, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry
        orrne zra, $0x100               @ set bit 8

        lsrs zra, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRLB:   @0xCB10
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        lsl zrb, $1
        orrne zrb, $0x01

        tst zrb, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands zrb, $0xFF         @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRLC:   @0xCB11
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        lsl zrc, $1
        orrne zrc, $0x01

        tst zrc, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands zrc, $0xFF         @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRLD:   @0xCB12
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        lsl zrd, $1
        orrne zrd, $0x01

        tst zrd, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands zrd, $0xFF         @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRLE:   @0xCB13
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        lsl zre, $1
        orrne zre, $0x01

        tst zre, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands zre, $0xFF         @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

cbRRB:   @0xCB18
        tst zrf, $flC           @ if carry
        orrne zrb, $0x100               @ set bit 8

        eor zrf, zrf            @ reset all flags

        tst zrb, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zrb, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRRC:   @0xCB19
        tst zrf, $flC           @ if carry
        orrne zrc, $0x100               @ set bit 8

        eor zrf, zrf            @ reset all flags

        tst zrc, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zrc, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRRD:   @0xCB1A
        tst zrf, $flC           @ if carry
        orrne zrd, $0x100               @ set bit 8

        eor zrf, zrf            @ reset all flags

        tst zrd, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zrd, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRRE:   @0xCB1B
        tst zrf, $flC           @ if carry
        orrne zre, $0x100               @ set bit 8

        eor zrf, zrf            @ reset all flags

        tst zre, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zre, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

cbSLAB:  @0xCB20
        eor zrf, zrf            @ reset all flags

        lsl zrb, $1

        tst zrb, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands zrb, $0xFF
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSLAC:  @0xCB21
        eor zrf, zrf            @ reset all flags

        lsl zrc, $1

        tst zrc, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands zrc, $0xFF
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSLAD:  @0xCB22
        eor zrf, zrf            @ reset all flags

        lsl zrd, $1

        tst zrd, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands zrd, $0xFF
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSLAE:  @0xCB23
        eor zrf, zrf            @ reset all flags

        lsl zre, $1

        tst zre, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands zre, $0xFF
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbSLAL:  @0xCB25
        eor zrf, zrf            @ reset all flags

        lsls lr, zhl, $0x09     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0x00FF0000
        orr zhl, lr, lsr $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbSLAA:  @0xCB27
        eor zrf, zrf            @ reset all flags

        lsl zra, $1

        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands zra, $0xFF
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSRAB:  @0xCB28
        eor zrf, zrf            @ reset all flags

        tst zrb, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zrb, $1
        orreq zrf, $flZ         @ set zero

        tst zrb, $0x40
        orrne zrb, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSRAC:  @0xCB29
        eor zrf, zrf            @ reset all flags

        tst zrc, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zrc, $1
        orreq zrf, $flZ         @ set zero

        tst zrc, $0x40
        orrne zrc, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSRAD:  @0xCB2A
        eor zrf, zrf            @ reset all flags

        tst zrd, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zrd, $1
        orreq zrf, $flZ         @ set zero

        tst zrd, $0x40
        orrne zrd, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSRAE:  @0xCB2B
        eor zrf, zrf            @ reset all flags

        tst zre, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zre, $1
        orreq zrf, $flZ         @ set zero

        tst zre, $0x40
        orrne zre, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSRAH:  @0xCB2C
        eor zrf, zrf            @ reset all flags

        asrs lr, zhl, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0xFF000000
        orr zhl, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

cbSWPB:  @0xCB30
        eor zrf, zrf            @ reset all flags

        lsl zrb, $0x04
        orr zrb, zrb, lsr $0x08

        ands zrb, $0xFF
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSWPC:  @0xCB31
        eor zrf, zrf            @ reset all flags

        lsl zrc, $0x04
        orr zrc, zrc, lsr $0x08

        ands zrc, $0xFF
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSWPD:  @0xCB32
        eor zrf, zrf            @ reset all flags

        lsl zrd, $0x04
        orr zrd, zrd, lsr $0x08

        ands zrd, $0xFF
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSWPE:  @0xCB33
        eor zrf, zrf            @ reset all flags

        lsl zre, $0x04
        orr zre, zre, lsr $0x08

        ands zre, $0xFF
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

cbSWPA:  @0xCB37
        eor zrf, zrf            @ reset all flags

        lsl zra, $0x04
        orr zra, zra, lsr $0x08

        ands zra, $0xFF
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSRLB:  @0xCB38
        eor zrf, zrf            @ reset all flags

        tst zrb, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zrb, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSRLC:  @0xCB39
        eor zrf, zrf            @ reset all flags

        tst zrc, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zrc, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSRLD:  @0xCB3A
        eor zrf, zrf            @ reset all flags

        tst zrd, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zrd, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSRLE:  @0xCB3B
        eor zrf, zrf            @ reset all flags

        tst zre, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zre, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbSRLH:  @0xCB3C
        eor zrf, zrf            @ reset all flags

        lsrs lr, zhl, $0x19     @ perform rotate
        orrcs zrf, $flC                 @ set carry
        orreq zrf, $flZ                 @ set zero

        bic zhl, $0xFF000000
        orr zhl, lr, lsl $0x18

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

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
        b cpu_inst_r

cbSRLA:  @0xCB3F
        eor zrf, zrf            @ reset all flags

        tst zra, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zra, $1
        orreq zrf, $flZ         @ set zero

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT0B:  @0xCB40
        bic zrf, $flN
        orr zrf, $flH

        tst zrb, $0x01
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT0C:  @0xCB41
        bic zrf, $flN
        orr zrf, $flH

        tst zrc, $0x01
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT0D:  @0xCB42
        bic zrf, $flN
        orr zrf, $flH

        tst zrd, $0x01
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT0E:  @0xCB43
        bic zrf, $flN
        orr zrf, $flH

        tst zre, $0x01
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT0H:  @0xCB44
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x01000000

        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT0L:  @0xCB45
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00010000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbBT0A:  @0xCB47
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x01
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT1B:  @0xCB48
        bic zrf, $flN
        orr zrf, $flH

        tst zrb, $0x02
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT1C:  @0xCB49
        bic zrf, $flN
        orr zrf, $flH

        tst zrc, $0x02
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT1D:  @0xCB4A
        bic zrf, $flN
        orr zrf, $flH

        tst zrd, $0x02
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT1E:  @0xCB4B
        bic zrf, $flN
        orr zrf, $flH

        tst zre, $0x02
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT1H:  @0xCB4C
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x02000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT1L:  @0xCB4D
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00020000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbBT1A:  @0xCB4F
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x02
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT2B:  @0xCB50
        bic zrf, $flN
        orr zrf, $flH

        tst zrb, $0x04
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT2C:  @0xCB51
        bic zrf, $flN
        orr zrf, $flH

        tst zrc, $0x04
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT2D:  @0xCB52
        bic zrf, $flN
        orr zrf, $flH

        tst zrd, $0x04
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT2E:  @0xCB53
        bic zrf, $flN
        orr zrf, $flH

        tst zre, $0x04
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT2H:  @0xCB54
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x04000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT2L:  @0xCB55
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00040000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbBT2A:  @0xCB57
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x04
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT3B:  @0xCB58
        bic zrf, $flN
        orr zrf, $flH

        tst zrb, $0x08
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT3C:  @0xCB59
        bic zrf, $flN
        orr zrf, $flH

        tst zrc, $0x08
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT3D:  @0xCB5A
        bic zrf, $flN
        orr zrf, $flH

        tst zrd, $0x08
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT3E:  @0xCB5B
        bic zrf, $flN
        orr zrf, $flH

        tst zre, $0x08
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT3H:  @0xCB5C
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x08000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT3L:  @0xCB5D
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00080000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbBT3A:  @0xCB5F
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x08
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT4B:  @0xCB60
        bic zrf, $flN
        orr zrf, $flH

        tst zrb, $0x10
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT4C:  @0xCB61
        bic zrf, $flN
        orr zrf, $flH

        tst zrc, $0x10
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT4D:  @0xCB62
        bic zrf, $flN
        orr zrf, $flH

        tst zrd, $0x10
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT4E:  @0xCB63
        bic zrf, $flN
        orr zrf, $flH

        tst zre, $0x10
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT4H:  @0xCB64
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x10000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT4L:  @0xCB65
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00100000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbBT4A:  @0xCB67
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x10
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT5B:  @0xCB68
        bic zrf, $flN
        orr zrf, $flH

        tst zrb, $0x20
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT5C:  @0xCB69
        bic zrf, $flN
        orr zrf, $flH

        tst zrc, $0x20
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT5D:  @0xCB6A
        bic zrf, $flN
        orr zrf, $flH

        tst zrd, $0x20
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT5E:  @0xCB6B
        bic zrf, $flN
        orr zrf, $flH

        tst zre, $0x20
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT5H:  @0xCB6C
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x20000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT5L:  @0xCB6D
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00200000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbBT5A:  @0xCB6F
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x20
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT6B:  @0xCB70
        bic zrf, $flN
        orr zrf, $flH

        tst zrb, $0x40
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT6C:  @0xCB71
        bic zrf, $flN
        orr zrf, $flH

        tst zrc, $0x40
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT6D:  @0xCB72
        bic zrf, $flN
        orr zrf, $flH

        tst zrd, $0x40
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT6E:  @0xCB73
        bic zrf, $flN
        orr zrf, $flH

        tst zre, $0x40
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT6H:  @0xCB74
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x40000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT6L:  @0xCB75
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00400000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbBT6A:  @0xCB77
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x40
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT7B:  @0xCB78
        bic zrf, $flN
        orr zrf, $flH

        tst zrb, $0x80
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT7C:  @0xCB79
        bic zrf, $flN
        orr zrf, $flH

        tst zrc, $0x80
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT7D:  @0xCB7A
        bic zrf, $flN
        orr zrf, $flH

        tst zrd, $0x80
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT7E:  @0xCB7B
        bic zrf, $flN
        orr zrf, $flH

        tst zre, $0x80
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT7H:  @0xCB7C
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x80000000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbBT7L:  @0xCB7D
        bic zrf, $flN
        orr zrf, $flH

        tst zhl, $0x00800000
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbBT7A:  @0xCB7F
        bic zrf, $flN
        orr zrf, $flH

        tst zra, $0x80
        orreq zrf, $flZ
        bicne zrf, $flZ

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS0B:  @0xCB80
        bic zrb, $0x01

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS0C:  @0xCB81
        bic zrc, $0x01

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS0D:  @0xCB82
        bic zrd, $0x01

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS0E:  @0xCB83
        bic zre, $0x01

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS0H:  @0xCB84
        bic zhl, $0x01000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS0L:  @0xCB85
        bic zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbRS0A:  @0xCB87
        bic zra, $0x01

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS1B:  @0xCB88
        bic zrb, $0x02

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS1C:  @0xCB89
        bic zrc, $0x02

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS1D:  @0xCB8A
        bic zrd, $0x02

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS1E:  @0xCB8B
        bic zre, $0x02

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS1H:  @0xCB8C
        bic zhl, $0x02000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS1L:  @0xCB8D
        bic zhl, $0x00020000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbRS1A:  @0xCB8F
        bic zra, $0x02

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS2B:  @0xCB90
        bic zrb, $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS2C:  @0xCB91
        bic zrc, $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS2D:  @0xCB92
        bic zrd, $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS2E:  @0xCB93
        bic zre, $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS2H:  @0xCB94
        bic zhl, $0x04000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS2L:  @0xCB95
        bic zhl, $0x00040000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbRS2A:  @0xCB97
        bic zra, $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS3B:  @0xCB98
        bic zrb, $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS3C:  @0xCB99
        bic zrc, $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS3D:  @0xCB9A
        bic zrd, $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS3E:  @0xCB9B
        bic zre, $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS3H:  @0xCB9C
        bic zhl, $0x08000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS3L:  @0xCB9D
        bic zhl, $0x00080000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbRS3A:  @0xCB9F
        bic zra, $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS4B:  @0xCBA0
        bic zrb, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS4C:  @0xCBA1
        bic zrc, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS4D:  @0xCBA2
        bic zrd, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS4E:  @0xCBA3
        bic zre, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS4H:  @0xCBA4
        bic zhl, $0x10000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS4L:  @0xCBA5
        bic zhl, $0x00100000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbRS4A:  @0xCBA7
        bic zra, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS5B:  @0xCBA8
        bic zrb, $0x20

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS5C:  @0xCBA9
        bic zrc, $0x20

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS5D:  @0xCBAA
        bic zrd, $0x20

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS5E:  @0xCBAB
        bic zre, $0x20

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS5H:  @0xCBAC
        bic zhl, $0x20000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS5L:  @0xCBAD
        bic zhl, $0x00200000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbRS5A:  @0xCBAF
        bic zra, $0x20

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS6B:  @0xCBB0
        bic zrb, $0x40

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS6C:  @0xCBB1
        bic zrc, $0x40

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS6D:  @0xCBB2
        bic zrd, $0x40

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS6E:  @0xCBB3
        bic zre, $0x40

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS6H:  @0xCBB4
        bic zhl, $0x40000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS6L:  @0xCBB5
        bic zhl, $0x00400000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbRS6A:  @0xCBB7
        bic zra, $0x40

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS7B:  @0xCBB8
        bic zrb, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS7C:  @0xCBB9
        bic zrc, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS7D:  @0xCBBA
        bic zrd, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS7E:  @0xCBBB
        bic zre, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS7H:  @0xCBBC
        bic zhl, $0x80000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbRS7L:  @0xCBBD
        bic zhl, $0x00800000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbRS7A:  @0xCBBF
        bic zra, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST0B:  @0xCBC0
        orr zrb, $0x01

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST0C:  @0xCBC1
        orr zrc, $0x01

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST0D:  @0xCBC2
        orr zrd, $0x01

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST0E:  @0xCBC3
        orr zre, $0x01

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST0H:  @0xCBC4
        orr zhl, $0x01000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST0L:  @0xCBC5
        orr zhl, $0x00010000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbST0A:  @0xCBC7
        orr zra, $0x01

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST1B:  @0xCBC8
        orr zrb, $0x02

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST1C:  @0xCBC9
        orr zrc, $0x02

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST1D:  @0xCBCA
        orr zrd, $0x02

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST1E:  @0xCBCB
        orr zre, $0x02

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST1H:  @0xCBCC
        orr zhl, $0x02000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST1L:  @0xCBCD
        orr zhl, $0x00020000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbST1A:  @0xCBCF
        orr zra, $0x02

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST2B:  @0xCBD0
        orr zrb, $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST2C:  @0xCBD1
        orr zrc, $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST2D:  @0xCBD2
        orr zrd, $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST2E:  @0xCBD3
        orr zre, $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST2H:  @0xCBD4
        orr zhl, $0x04000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST2L:  @0xCBD5
        orr zhl, $0x00040000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbST2A:  @0xCBD7
        orr zra, $0x04

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST3B:  @0xCBD8
        orr zrb, $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST3C:  @0xCBD9
        orr zrc, $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST3D:  @0xCBDA
        orr zrd, $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST3E:  @0xCBDB
        orr zre, $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST3H:  @0xCBDC
        orr zhl, $0x08000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST3L:  @0xCBDD
        orr zhl, $0x00080000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbST3A:  @0xCBDF
        orr zra, $0x08

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST4B:  @0xCBE0
        orr zrb, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST4C:  @0xCBE1
        orr zrc, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST4D:  @0xCBE2
        orr zrd, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST4E:  @0xCBE3
        orr zre, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST4H:  @0xCBE4
        orr zhl, $0x10000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST4L:  @0xCBE5
        orr zhl, $0x00100000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbST4A:  @0xCBE7
        orr zra, $0x10

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST5B:  @0xCBE8
        orr zrb, $0x20

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST5C:  @0xCBE9
        orr zrc, $0x20

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST5D:  @0xCBEA
        orr zrd, $0x20

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST5E:  @0xCBEB
        orr zre, $0x20

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST5H:  @0xCBEC
        orr zhl, $0x20000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST5L:  @0xCBED
        orr zhl, $0x00200000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbST5A:  @0xCBEF
        orr zra, $0x20

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST6B:  @0xCBF0
        orr zrb, $0x40

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST6C:  @0xCBF1
        orr zrc, $0x40

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST6D:  @0xCBF2
        orr zrd, $0x40

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST6E:  @0xCBF3
        orr zre, $0x40

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST6H:  @0xCBF4
        orr zhl, $0x40000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST6L:  @0xCBF5
        orr zhl, $0x00400000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbST6A:  @0xCBF7
        orr zra, $0x40

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST7B:  @0xCBF8
        orr zrb, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST7C:  @0xCBF9
        orr zrc, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST7D:  @0xCBFA
        orr zrd, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST7E:  @0xCBFB
        orr zre, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST7H:  @0xCBFC
        orr zhl, $0x80000000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

cbST7L:  @0xCBFD
        orr zhl, $0x00800000

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

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
        b cpu_inst_r

cbST7A:  @0xCBFF
        orr zra, $0x80

        add zil, $2
        add zpc, $0x00010000
        b cpu_inst_r

        .end
