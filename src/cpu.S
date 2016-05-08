/******************************************************************************
 * \file cpu.S
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
 * | rh         | r9         |
 * | rl         | r10        |
 * | pc         | r11        |
 * | il         | r12        |
 * | sp         | r13 (sp)   |
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

        .data
Z80RS:  .space 52
Z80RS_E:
SYSRS:  .space 44
SYSRS_E:
                  @0/8     @1/9     @2/A    @3/B    @4/C    @5/D    @6/E    @7/F
ZOPS:   .word    opNOP,opLDBCnn, opLDBCA,  opIBC,   opIB,   opDB, opLDBn, opRLCA  @0
        .word opLDnnSP, opAHLBC, opLDABC,  opDBC,   opIC,   opDC, opLDCn, opRRCA
        .word   opSTOP,opLDDEnn, opLDDEA,  opIDE,   opID,   opDD, opLDDn,  opRLA  @1
        .word    opJRn, opAHLDE, opLDADE,  opDDE,   opIE,   opDE, opLDEn,  opRRA
        .word  opJRNZn,opLDHLnn,opLDHLiA,  opIHL,   opIH,   opDH, opLDHn,  opDAA  @2
        .word   opJRZn, opAHLHL,opLDAHLi,  opDHL,   opIL,   opDL, opLDLn,  opCPL
        .word  opJRNCn,opLDSPnn,opLDHLdA,  opISP, opIHLm, opDHLm,opLDHLn,  opSCF  @3
        .word   opJRCn, opAHLSP,opLDAHLd,  opDSP,   opIA,   opDA, opLDAn,  opCCF
        .word   opLDBB,  opLDBC,  opLDBD, opLDBE, opLDBH, opLDBL,opLDBHL, opLDBA  @4
        .word   opLDCB,  opLDCC,  opLDCD, opLDCE, opLDCH, opLDCL,opLDCHL, opLDCA
        .word   opLDDB,  opLDDC,  opLDDD, opLDDE, opLDDH, opLDDL,opLDDHL, opLDDA  @5
        .word   opLDEB,  opLDEC,  opLDED, opLDEE, opLDEH, opLDEL,opLDEHL, opLDEA
        .word   opLDHB,  opLDHC,  opLDHD, opLDHE, opLDHH, opLDHL,opLDHHL, opLDHA  @6
        .word   opLDLB,  opLDLC,  opLDLD, opLDLE, opLDLH, opLDLL,opLDLHL, opLDLA
        .word  opLDHLB, opLDHLC, opLDHLD,opLDHLE,opLDHLH,opLDHLL, opHALT,opLDHLA  @7
        .word   opLDAB,  opLDAC,  opLDAD, opLDAE, opLDAH, opLDAL,opLDAHL, opLDAA
        .word    opAAB,   opAAC,   opAAD,  opAAE,  opAAH,  opAAL, opAAHL,  opAAA  @8
        .word   opAcAB,  opAcAC,  opAcAD, opAcAE, opAcAH, opAcAL,opAcAHL, opAcAA
        .word    opSAB,   opSAC,   opSAD,  opSAE,  opSAH,  opSAL, opSAHL,  opSAA  @9
        .word   opScAB,  opScAC,  opScAD, opScAE, opScAH, opScAL,opScAHL, opScAA
        .word   opANAB,  opANAC,  opANAD, opANAE, opANAH, opANAL,opANAHL, opANAA  @A
        .word   opXOAB,  opXOAC,  opXOAD, opXOAE, opXOAH, opXOAL,opXOAHL, opXOAA
        .word   opORAB,  opORAC,  opORAD, opORAE, opORAH, opORAL,opORAHL, opORAA  @B
        .word    opCAB,   opCAC,   opCAD,  opCAE,  opCAH,  opCAL, opCAHL,  opCAA
        .word  opRETNZ, opPOPBC,opJPNZnn, opJPnn,opCNZnn,opPUSBC,  opAAn, opR00H  @C
        .word   opRETZ,   opRET, opJPZnn,   opNI, opCZnn,  opCnn, opAcAn, opR08H
        .word  opRETNC, opPOPDE,opJPNCnn,   opNI,opCNCnn,opPUSDE,  opSAn, opR10H  @D
        .word   opRETC,  opRETI, opJPCnn,   opNI, opCCnn,   opNI, opScAn, opR18H
        .word  opLDFnA, opPOPHL, opLDFCA,   opNI,   opNI,opPUSHL, opANAn, opR20H  @E
        .word   opASPn,  opJPHL, opLDnnA,   opNI,   opNI,   opNI, opXOAn, opR28H
        .word  opLDAFn, opPOPAF, opLDAFC,   opDI,   opNI,opPUSAF, opORAn, opR30H  @F
        .word opLDHLSn, opLDSHL, opLDAnn,   opEI,   opNI, opEXIT,  opCAn, opR38H

        .text
        .global cpu_init
cpu_init:
        ldr r0, =SYSRS
        stmea r0, {r4-r14}

        ldr zop, =ZOPS
        mov zra, $0xFF
        mov zrb, $0xFF
        mov zrc, $0
        mov zrd, $0
        mov zre, $0
        mov zrf, $0xFF
        mov zrh, $0
        mov zrl, $0
        mov zpc, $0
        mov zil, $1
        mov zsp, $0xFF

        ldr r1, =Z80RS
        stmea r1, {r2-r14}

        ldr r0, =SYSRS_E
        ldmea r0, {r4-r13, pc}

        .global cpu_dispatch
cpu_dispatch:
        ldr r0, =SYSRS
        stmea r0, {r4-r14}

        ldr r1, =Z80RS_E
        ldmea r1, {r2-r14}

        /* Z80 SYSTEM READY */
        /* AT THIS POINT, THE ONLY PATH BACK TO LR */
        /* IS THE SPECIAL 0xFD INSTRUCTION, opEXIT */

cpu_step:
        subs zil, $1
        bpl cpu_step

        @ fix PC overflow
        bic zpc, $0x10000

        /* DEBUG */
        bl cpu_stat

        /* Load Instruction */
        bl mmu_ri
        ldrls pc, [zop, r1, lsl $2]
cpu_inst_r:
        b cpu_step

cpu_stat:
        ldr r0, =Z80RS
        stmea r0, {r2-r14}

        bl mmu_ri

        ldr r0, =SYSRS_E
        ldmea r0, {r4-r14}

        ldr r0, =Z80RS
        bl stat_print

        ldr r0, =Z80RS_E
        ldmea r0, {r2-r13, pc}

        .ltorg    @ keep literal pool close

/* INSTRUCTIONS */
opNOP:   @0x00
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDBCnn:@0x01
        bl mmu_rih1
        and zrc, r1, $0xFF
        lsr zrb, r1, $0x08

        mov zil, $12
        add zpc, $3
        b cpu_inst_r

opLDBCA: @0x02
        orr r0, zrc, zrb, lsl $0x08
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIBC:   @0x03
        orr r0, zrc, zrb, lsl $0x08

        add r0, $1

        and zrc, r0, $0xFF
        lsr zrb, r0, $0x08
        and zrb, $0xFF                  @ clear any carried bit(s)

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIB:    @0x04
        bic zrf, $flN           @ reset subtract

        add r0, zrb, $1

        eor r1, r0, zrb
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zrb, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opDB:    @0x05
        orr zrf, $flN           @ set subtract

        add r0, zrb, $0xFF      @ subtract 1

        eor r1, zrb, $0xFF
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zrb, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDBn:  @0x06
        bl mmu_ri1

        mov zrb, r1
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opRLCA:  @0x07
        eor zrf, zrf            @ reset all flags

        lsl zra, $1
        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry
        orrne zra, $0x01                @ set bit 0

        ands zra, $0xFF         @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDnnSP:@0x08
        bl mmu_rih1
        orr r0, sp, r1, lsl $0x10
        bl mmu_wh

        mov zil, $20
        add zpc, $3
        b cpu_inst_r

opAHLBC: @0x09
        bic zrf, $flN           @ reset subtract

        orr r0, zrl, zrh, lsl $0x08     @ put HL in r0
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

        and zrl, lr, $0xFF
        lsr zrh, lr, $0x08
        and zrh, $0xFF                  @ clear any carried bit(s)

        mov zra, r0
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDABC: @0x0A
        orr r0, zrc, zrb, lsl $0x08
        bl mmu_rb

        mov zra, r1
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opDBC:   @0x0B
        orr r0, zrc, zrb, lsl $0x08

        sub r0, $1

        and zrc, r0, $0xFF
        lsr zrb, r0, $0x08
        and zrb, $0xFF                  @ clear any carried bit(s)

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIC:    @0x0C
        bic zrf, $flN           @ reset subtract

        add r0, zrc, $1

        eor r1, r0, zrc
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        andne r0, $0xFF                 @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zrc, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opDC:    @0x0D
        orr zrf, $flN           @ set subtract

        add r0, zrc, $0xFF      @ subtract 1

        eor r1, zrc, $0xFF
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zrc, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDCn:  @0x0E
        bl mmu_ri1

        mov zrc, r1
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opRRCA:  @0x0F
        eor zrf, zrf            @ reset all flags

        tst zra, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry
        orrne zra, $0x100               @ set bit 8

        lsrs zra, $1
        orreq zrf, $flZ         @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opSTOP:  @0x10
        @ TODO: Wait for button press

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDDEnn:@0x11
        bl mmu_rih1
        and zre, r1, $0xFF
        lsr zrd, r1, $0x08

        mov zil, $12
        add zpc, $3
        b cpu_inst_r

opLDDEA: @0x12
        orr r0, zre, zrd, lsl $0x08
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIDE:   @0x13
        orr r0, zre, zrd, lsl $0x08

        add r0, $1

        and zre, r0, $0xFF
        lsr zrd, r0, $0x08
        and zrd, $0xFF                  @ clear any carried bit(s)

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opID:    @0x14
        bic zrf, $flN           @ reset subtract

        add r0, zrd, $1

        eor r1, r0, zrd
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zrd, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opDD:    @0x15
        orr zrf, $flN           @ set subtract

        add r0, zrd, $0xFF      @ subtract 1

        eor r1, zrd, $0xFF
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zrd, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDDn:  @0x16
        bl mmu_ri1

        mov zrd, r1
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opRLA:   @0x17
        tst zrf, $flC

        eor zrf, zrf            @ reset all flags

        lsl zra, $1
        orrne zra, $0x01

        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set carry

        ands zra, $0xFF         @ clear any carried bit(s)
        orreq zrf, $flZ         @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opJRn:   @0x18
        bl mmu_ri1
        sxtab zpc, zpc, r1

        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opAHLDE: @0x19
        bic zrf, $flN           @ reset subtract

        orr r0, zrl, zrh, lsl $0x08     @ put HL in r0
        orr r1, zre, zrd, lsl $0x08     @ put DE in r1
        add lr, r0, r1

        eor r1, r1, lr
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x1000         @ if bit 12 is set
        orrne zrf, $flH                 @ set half-carry
        biceq zrf, $flH                 @ reset half-carry

        tst r1, $0x10000        @ if bit 16 is set
        orrne zrf, $flC                 @ set full-carry
        biceq zrf, $flC                 @ reset full-carry

        and zrl, lr, $0xFF
        lsr zrh, lr, $0x08
        and zrh, $0xFF                  @ clear any carried bit(s)

        mov zra, r0
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDADE: @0x1A
        orr r0, zre, zrd, lsl $0x08
        bl mmu_rb

        mov zra, r1
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opDDE:   @0x1B
        orr r0, zre, zrd, lsl $0x08

        sub r0, $1

        and zre, r0, $0xFF
        lsr zrd, r0, $0x08
        and zrd, $0xFF                  @ clear any carried bit(s)

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIE:    @0x1C
        bic zrf, $flN           @ reset subtract

        add r0, zre, $1

        eor r1, r0, zre
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zre, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opDE:    @0x1D
        orr zrf, $flN           @ set subtract

        add r0, zre, $0xFF      @ subtract 1

        eor r1, zre, $0xFF
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zre, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDEn:  @0x1E
        bl mmu_ri1

        mov zre, r1
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opRRA :  @0x1F
        tst zrf, $flC           @ if carry
        orrne zra, $0x100               @ set bit 8

        eor zrf, zrf            @ reset all flags

        tst zra, $0x01          @ if bit 0 is set
        orrne zrf, $flC                 @ set carry

        lsrs zra, $1
        orreq zrf, $flZ         @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opJRNZn: @0x20
        mov zil, $8
        add zpc, $2

        tst zrf, $flZ
        bne cpu_inst_r

        bl mmu_ri1
        sxtab zpc, zpc, r1

        b cpu_inst_r

opLDHLnn:@0x21
        bl mmu_rih1
        and zrl, r1, $0xFF
        lsr zrh, r1, $0x08

        mov zil, $12
        add zpc, $3
        b cpu_inst_r

opLDHLiA:@0x22
        orr r0, zrl, zrh, lsl $0x08
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        add zrl, $1
        cmp zrl, $0xFF
        movhi zrl, $0x00
        addhi zrh, $1
        cmphi zrh, $0xFF
        movhi zrh, $0x00

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIHL:   @0x23
        orr r0, zrl, zrh, lsl $0x08

        add r0, $1

        and zrl, r0, $0xFF
        lsr zrh, r0, $0x08
        and zrh, $0xFF                  @ clear any carried bit(s)

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIH:    @0x24
        bic zrf, $flN           @ reset subtract

        add r0, zrh, $1

        eor r1, r0, zrh
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zrh, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opDH:    @0x25
        orr zrf, $flN           @ set subtract

        add r0, zrh, $0xFF      @ subtract 1

        eor r1, zrh, $0xFF
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zrh, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDHn:  @0x26
        bl mmu_ri1

        mov zrh, r1
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opDAA:   @0x27
        tst zrf, $flN
        bne opDAA_neg

        tst zrf, $flH           @ if half-carry
        andeq r0, zra, $0xF
        cmpeq r0, $0x0A         @ or lower nibble of A > 9
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

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opJRZn:  @0x28
        mov zil, $8
        add zpc, $2

        tst zrf, $flZ
        beq cpu_inst_r

        bl mmu_ri1
        sxtab zpc, zpc, r1

        b cpu_inst_r

opAHLHL: @0x29
        bic zrf, $flN           @ reset subtract

        orr r0, zrl, zrh, lsl $0x08     @ put HL in r0
        add r1, r0, r0

        tst r1, $0x1000         @ if bit 12 is set
        orrne zrf, $flH                 @ set half-carry
        biceq zrf, $flH                 @ reset half-carry

        tst r1, $0x10000        @ if bit 16 is set
        orrne zrf, $flC                 @ set full-carry
        biceq zrf, $flC                 @ reset full-carry

        and zrl, r1, $0xFF
        lsr zrh, r1, $0x08
        and zrh, $0xFF                  @ clear any carried bit(s)

        mov zra, r0
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDAHLi:@0x2A
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb
        mov zra, r1

        add zrl, $1
        cmp zrl, $0xFF
        movhi zrl, $0x00
        addhi zrh, $1
        cmphi zrh, $0xFF
        movhi zrh, $0x00

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opDHL:   @0x2B
        orr r0, zrl, zrh, lsl $0x08

        sub r0, $1

        and zrl, r0, $0xFF
        lsr zrh, r0, $0x08
        and zrh, $0xFF                  @ clear any carried bit(s)

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIL:    @0x2C
        bic zrf, $flN           @ reset subtract

        add r0, zrl, $1

        eor r1, r0, zrl
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zrl, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opDL:    @0x2D
        orr zrf, $flN           @ set subtract

        add r0, zrl, $0xFF      @ subtract 1

        eor r1, zrl, $0xFF
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zrl, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDLn:  @0x2E
        bl mmu_ri1

        mov zrl, r1
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opCPL:   @0x2F
        mvn zra, zra
        orr zrf, $flN
        orr zrf, $flH

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opJRNCn: @0x30
        mov zil, $8
        add zpc, $2

        tst zrf, $flC
        bne cpu_inst_r

        bl mmu_ri1
        sxtab zpc, zpc, r1

        b cpu_inst_r

opLDSPnn:@0x31
        bl mmu_rih1
        mov zsp, r1

        mov zil, $12
        add zpc, $3
        b cpu_inst_r

opLDHLdA:@0x32
        orr r0, zrl, zrh, lsl $0x08
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        subs zrl, $1
        movmi zrl, $0xFF
        submis zrh, $1
        movmi zrh, $0xFF

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opISP:   @0x33
        add zsp, $1
        bic zsp, $0x10000               @ clear any carried bit(s)

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIHLm:  @0x34
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        bic zrf, $flN           @ reset subtract

        add r0, r1, $1

        eor r1, r0, r1
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        orr r1, zrl, zrh, lsl $0x08
        orr r0, r0, r1, lsl $16
        bl mmu_wb

        mov zil, $12
        add zpc, $1
        b cpu_inst_r

opDHLm:  @0x35
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        orr zrf, $flN           @ set subtract

        add r0, r1, $0xFF       @ subtract 1

        eor r1, r1, $0xFF
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        orr r1, zrl, zrh, lsl $0x08
        orr r0, r0, r1, lsl $16
        bl mmu_wb

        mov zil, $12
        add zpc, $1
        b cpu_inst_r

opLDHLn: @0x36
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_ri1
        orr r0, r1, r0, lsl $0x10
        bl mmu_wb

        mov zil, $12
        add zpc, $2
        b cpu_inst_r

opSCF:   @0x37
        bic zrf, $flN           @ reset subtract
        bic zrf, $flH           @ reset half-carry
        orr zrf, $flC           @ set carry

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opJRCn: @0x38
        mov zil, $8
        add zpc, $2

        tst zrf, $flC
        beq cpu_inst_r

        bl mmu_ri1
        sxtab zpc, zpc, r1

        b cpu_inst_r

opAHLSP: @0x39
        bic zrf, $flN           @ reset subtract

        orr r1, zrl, zrh, lsl $0x08     @ put HL in r1
        add r0, r1, sp

        eor r1, r1, sp
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x1000         @ if bit 12 is set
        orrne zrf, $flH                 @ set half-carry
        biceq zrf, $flH                 @ reset half-carry

        tst r1, $0x10000        @ if bit 16 is set
        orrne zrf, $flC                 @ set full-carry
        biceq zrf, $flC                 @ reset full-carry

        and zrl, r0, $0xFF
        lsr zrh, r0, $0x08
        and zrh, $0xFF                  @ clear any carried bit(s)

        mov zra, r0
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDAHLd:@0x3A
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb
        mov zra, r1

        subs zrl, $1
        movmi zrl, $0xFF
        submis zrh, $1
        movmi zrh, $0xFF

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opDSP:   @0x3B
        sub zsp, $1

        bic zsp, $0x00FF0000            @ clear any carried bit(s)
        bic zsp, $0xFF000000            @ clear any carried bit(s)

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIA:    @0x3C
        bic zrf, $flN           @ reset subtract

        add r0, zra, $1

        eor r1, r0, zra
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opDA:    @0x3D
        orr zrf, $flN           @ set subtract

        add r0, zra, $0xFF      @ subtract 1

        eor r1, zra, $0xFF
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        biceq zrf, $flH                 @ reset half-carry
        orrne zrf, $flH                 @ set half-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero
        bicne zrf, $flZ                 @ reset zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDAn:  @0x3E
        bl mmu_ri1

        mov zra, r1
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opCCF:   @0x3F
        bic zrf, $flN           @ reset subtract
        bic zrf, $flH           @ reset half-carry
        eor zrf, $flC           @ complement carry

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDBB:  @0x40
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDBC:  @0x41
        mov zrb, zrc
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDBD:  @0x42
        mov zrb, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDBE:  @0x43
        mov zrb, zre
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDBH:  @0x44
        mov zrb, zrh
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDBL:  @0x45
        mov zrb, zrl
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDBHL: @0x46
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        mov zrb, r1
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDBA:  @0x47
        mov zrb, zra
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDCB:  @0x48
        mov zrc, zrb
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDCC:  @0x49
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDCD:  @0x4A
        mov zrc, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDCE:  @0x4B
        mov zrc, zre
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDCH:  @0x4C
        mov zrc, zrh
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDCL:  @0x4D
        mov zrc, zrl
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDCHL: @0x4E
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        mov zrc, r1
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDCA:  @0x4F
        mov zrc, zra
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDDB:  @0x50
        mov zrd, zrb
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDDC:  @0x51
        mov zrd, zrc
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDDD:  @0x52
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDDE:  @0x53
        mov zrd, zre
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDDH:  @0x54
        mov zrd, zrh
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDDL:  @0x55
        mov zrd, zrl
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDDHL: @0x56
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        mov zrd, r1
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDDA:  @0x57
        mov zrd, zra
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDEB:  @0x58
        mov zre, zrb
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDEC:  @0x59
        mov zre, zrc
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDED:  @0x5A
        mov zre, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDEE:  @0x5B
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDEH:  @0x5C
        mov zre, zrh
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDEL:  @0x5D
        mov zre, zrl
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDEHL: @0x5E
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        mov zre, r1
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDEA:  @0x5F
        mov zre, zra
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDHB:  @0x60
        mov zrh, zrb
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDHC:  @0x61
        mov zrh, zrc
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDHD:  @0x62
        mov zrh, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDHE:  @0x63
        mov zrh, zre
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDHH:  @0x64
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDHL:  @0x65
        mov zrh, zrl
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDHHL: @0x66
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        mov zrh, r1
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDHA:  @0x67
        mov zrh, zra
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDLB:  @0x68
        mov zrl, zrb
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDLC:  @0x69
        mov zrl, zrc
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDLD:  @0x6A
        mov zrl, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDLE:  @0x6B
        mov zrl, zre
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDLH:  @0x6C
        mov zrl, zrh
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDLL:  @0x6D
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDLHL: @0x6E
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        mov zrl, r1
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDLA:  @0x6F
        mov zrl, zra
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDHLB: @0x70
        orr r0, zrl, zrh, lsl $0x08
        orr r0, zrb, r0, lsl $0x10
        bl mmu_wb

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDHLC: @0x71
        orr r0, zrl, zrh, lsl $0x08
        orr r0, zrc, r0, lsl $0x10
        bl mmu_wb

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDHLD: @0x72
        orr r0, zrl, zrh, lsl $0x08
        orr r0, zrd, r0, lsl $0x10
        bl mmu_wb

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDHLE: @0x73
        orr r0, zrl, zrh, lsl $0x08
        orr r0, zre, r0, lsl $0x10
        bl mmu_wb

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDHLH: @0x74
        orr r0, zrl, zrh, lsl $0x08
        orr r0, zrh, r0, lsl $0x10
        bl mmu_wb

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDHLL: @0x75
        orr r0, zrl, zrh, lsl $0x08
        orr r0, zrl, r0, lsl $0x10
        bl mmu_wb

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opHALT:  @0x76
        @ TODO: Wait for interrupt

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDHLA: @0x77
        orr r0, zrl, zrh, lsl $0x08
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDAB:  @0x78
        mov zra, zrb
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDAC:  @0x79
        mov zra, zrc
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDAD:  @0x7A
        mov zra, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDAE:  @0x7B
        mov zra, zre
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDAH:  @0x7C
        mov zra, zrh
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDAL:  @0x7D
        mov zra, zrl
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDAHL: @0x7E
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        mov zra, r1
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDAA:  @0x7F
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAAH:   @0x84
        eor zrf, zrf            @ reset all flags

        add r0, zra, zrh

        eor r1, r0, zra
        eor r1, r1, zrh         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAAL:   @0x85
        eor zrf, zrf            @ reset all flags

        add r0, zra, zrl

        eor r1, r0, zra
        eor r1, r1, zrl         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAAHL:  @0x86
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        add r0, zra, r1

        eor r0, r0, zra
        eor r0, r0, r1          @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        add zra, r1
        ands zra, $0xFF                 @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zil, $8
        add zpc, $1
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

        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1

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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAcAH:  @0x8C
        tst zrf, $flC
        moveq r0, zrh
        addne r0, zrh, $1

        eor zrf, zrf            @ reset all flags

        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zrh         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAcAL:  @0x8D
        tst zrf, $flC
        moveq r0, zrl
        addne r0, zrl, $1

        eor zrf, zrf            @ reset all flags

        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zrl         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAcAHL: @0x8E
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        tst zrf, $flC
        moveq r0, r1
        addne r0, r1, $1

        eor zrf, zrf            @ reset all flags

        add r0, zra

        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $8
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opSAH:   @0x94
        mov zrf, $flN           @ set only subtract

        mvn r1, zrh
        add r1, $1              @ 2's compliment
        add r0, zra, r1

        eor r1, r0, zra
        eor r1, r1, zrh         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opSAL:   @0x95
        mov zrf, $flN           @ set only subtract

        mvn r1, zrl
        add r1, $1              @ 2's compliment
        add r0, zra, r1

        eor r1, r0, zra
        eor r1, r1, zrl         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opSAHL:  @0x96
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        mov zrf, $flN           @ set only subtract

        mvn r0, r1
        add r0, $1              @ 2's compliment
        add r0, zra

        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opSAA:   @0x97
        mov zrf, $flN           @ set only subtract
        orr zrf, $flZ           @ set zero

        mov zra, $0
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
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

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opScAH:  @0x9C
        mvn r1, zrh
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r0, zra, r1

        mov zrf, $flN           @ set only subtract

        eor r1, r0, zra
        eor r1, r1, zrh         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opScAL:  @0x9D
        mvn r1, zrl
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        add r0, zra, r1

        mov zrf, $flN           @ set only subtract

        eor r1, r0, zra
        eor r1, r1, zrl         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opScAHL: @0x9E
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        mvn r0, r1
        tst zrf, $flC
        addeq r0, $1            @ 2's compliment
        add r0, zra

        mov zrf, $flN           @ set only subtract

        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opScAA:  @0x9F
        tst zrf, $flC
        moveq zra, $0x00
        moveq zrf, $flZ
        movne zra, $0xFF
        movne zrf, $flC
        orrne zrf, $flH

        orr zrf, $flN

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAB:  @0xA0
        mov zrf, $flH           @ set only half-carry

        ands zra, zrb
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAC:  @0xA1
        mov zrf, $flH           @ set only half-carry

        ands zra, zrc
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAD:  @0xA2
        mov zrf, $flH           @ set only half-carry

        ands zra, zrd
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAE:  @0xA3
        mov zrf, $flH           @ set only half-carry

        ands zra, zre
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAH:  @0xA4
        mov zrf, $flH           @ set only half-carry

        ands zra, zrh
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAL:  @0xA5
        mov zrf, $flH           @ set only half-carry

        ands zra, zrl
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAHL: @0xA6
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        mov zrf, $flH           @ set only half-carry

        ands zra, r1
        orreq zrf, $flZ                 @ set zero

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opANAA:  @0xA7
        mov zrf, $flH           @ set only half-carry

        ands zra, zra
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opXOAB:  @0xA8
        eor zrf, zrf            @ reset all flags

        eors zra, zrb
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opXOAC:  @0xA9
        eor zrf, zrf            @ reset all flags

        eors zra, zrc
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opXOAD:  @0xAA
        eor zrf, zrf            @ reset all flags

        eors zra, zrd
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opXOAE:  @0xAB
        eor zrf, zrf            @ reset all flags

        eors zra, zre
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opXOAH:  @0xAC
        eor zrf, zrf            @ reset all flags

        eors zra, zrh
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opXOAL:  @0xAD
        eor zrf, zrf            @ reset all flags

        eors zra, zrl
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opXOAHL: @0xAE
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        eors zra, r1
        orreq zrf, $flZ                 @ set zero

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opXOAA:  @0xAF
        eor zrf, zrf            @ reset all flags

        eors zra, zra
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opORAB:  @0xB0
        eor zrf, zrf            @ reset all flags

        orrs zra, zrb
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opORAC:  @0xB1
        eor zrf, zrf            @ reset all flags

        orrs zra, zrc
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opORAD:  @0xB2
        eor zrf, zrf            @ reset all flags

        orrs zra, zrd
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opORAE:  @0xB3
        eor zrf, zrf            @ reset all flags

        orrs zra, zre
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opORAH:  @0xB4
        eor zrf, zrf            @ reset all flags

        orrs zra, zrh
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opORAL:  @0xB5
        eor zrf, zrf            @ reset all flags

        orrs zra, zrl
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opORAHL: @0xB6
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        orrs zra, r1
        orreq zrf, $flZ                 @ set zero

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opORAA:  @0xB7
        eor zrf, zrf            @ reset all flags

        orrs zra, zra
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
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

        mov zil, $4
        add zpc, $1
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

        mov zil, $4
        add zpc, $1
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

        mov zil, $4
        add zpc, $1
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

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opCAH:   @0xBC
        mov zrf, $flN           @ set only subtract

        mvn r0, zrh
        add r0, $1              @ 2's compliment
        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zrh         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opCAL:   @0xBD
        mov zrf, $flN           @ set only subtract

        mvn r0, zrl
        add r0, $1              @ 2's compliment
        add r0, zra

        eor r1, r0, zra
        eor r1, r1, zrl         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opCAHL:  @0xBE
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        mov zrf, $flN           @ set only subtract

        mvn r0, r1
        add r0, $1              @ 2's compliment
        add r0, zra

        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opCAA:   @0xBF
        mov zrf, $flN           @ set only subtract
        orr zrf, $flZ           @ set zero

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opRETNZ: @0xC0
        mov zil, $8

        tst zrf, $flZ
        addne zpc, $1
        bne cpu_inst_r

        mov r0, zsp
        bl mmu_rh

        add zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000

        mov zpc, r1

        b cpu_inst_r

opPOPBC: @0xC1
        mov r0, zsp
        add zsp, $2
        bl mmu_rh
        and zrb, r1, $0xFF
        lsr zrc, r1, $0x08

        mov zil, $12
        add zpc, $1
        b cpu_inst_r

opJPNZnn:@0xC2
        mov zil, $12

        tst zrf, $flZ
        addne zpc, $3
        bne cpu_inst_r

        bl mmu_rih1
        mov zpc, r1
        b cpu_inst_r

opJPnn:  @0xC3
        bl mmu_rih1
        mov zpc, r1

        mov zil, $12
        b cpu_inst_r

opCNZnn: @0xC4
        mov zil, $12
        add zpc, $3

        tst zrf, $flZ
        bne cpu_inst_r

        bl mmu_rih1

        bic r0, zpc, $0x00FF0000
        bic r0, $0xFF000000
        mov zpc, r1

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        b cpu_inst_r

opPUSBC: @0xC5
        sub zsp, $2
        orr r0, zrc, zrb, lsl $0x08
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $16
        add zpc, $1
        b cpu_inst_r

opAAn:   @0xC6
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        add r0, zra, r1

        eor r0, r0, zra
        eor r0, r0, r1          @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        add zra, r1
        ands zra, $0xFF                 @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opR00H:  @0xC7
        add r0, zpc, $3
        bic r0, $0x00FF0000
        bic r0, $0xFF000000

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $32
        mov zpc, $0x00
        b cpu_inst_r

opRETZ:  @0xC8
        mov zil, $8

        tst zrf, $flZ
        addeq zpc, $1
        beq cpu_inst_r

        mov r0, zsp
        bl mmu_rh

        add zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000

        mov zpc, r1

        b cpu_inst_r

opRET:   @0xC9
        mov r0, zsp
        bl mmu_rh

        add zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000

        mov zpc, r1

        mov zil, $8
        b cpu_inst_r

opJPZnn: @0xCA
        mov zil, $12

        tst zrf, $flZ
        addeq zpc, $3
        beq cpu_inst_r

        bl mmu_rih1
        mov zpc, r1
        b cpu_inst_r

opCZnn:  @0xCC
        mov zil, $12
        add zpc, $3

        tst zrf, $flZ
        beq cpu_inst_r

        bl mmu_rih1

        bic r0, zpc, $0x00FF0000
        bic r0, $0xFF000000
        mov zpc, r1

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        b cpu_inst_r

opCnn:   @0xCD
        bl mmu_rih1

        add r0, zpc, $3
        bic r0, $0x00FF0000
        bic r0, $0xFF000000
        mov zpc, r1

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $12
        b cpu_inst_r

opAcAn:  @0xCE
        bl mmu_ri1

        tst zrf, $flC           @ handle possible carry
        moveq r0, r1
        addne r0, r1, $1

        eor zrf, zrf            @ reset all flags

        add r0, zra

        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opR08H:  @0xCF
        add r0, zpc, $3
        bic r0, $0x00FF0000
        bic r0, $0xFF000000

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $32
        mov zpc, $0x08
        b cpu_inst_r

opRETNC: @0xD0
        mov zil, $8

        tst zrf, $flC
        addne zpc, $1
        bne cpu_inst_r

        mov r0, zsp
        bl mmu_rh

        add zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000

        mov zpc, r1

        b cpu_inst_r

opPOPDE: @0xD1
        mov r0, zsp
        add zsp, $2
        bl mmu_rh
        and zrd, r1, $0xFF
        lsr zre, r1, $0x08

        mov zil, $12
        add zpc, $1
        b cpu_inst_r

opJPNCnn:@0xD2
        mov zil, $12

        tst zrf, $flC
        addne zpc, $3
        bne cpu_inst_r

        bl mmu_rih1
        mov zpc, r1
        b cpu_inst_r

opCNCnn: @0xD4
        mov zil, $12
        add zpc, $3

        tst zrf, $flC
        bne cpu_inst_r

        bl mmu_rih1

        bic r0, zpc, $0x00FF0000
        bic r0, $0xFF000000
        mov zpc, r1

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        b cpu_inst_r

opPUSDE: @0xD5
        sub zsp, $2
        orr r0, zre, zrd, lsl $0x08
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $16
        add zpc, $1
        b cpu_inst_r

opSAn:   @0xD6
        bl mmu_ri1

        mov zrf, $flN           @ set only subtract

        mvn r0, r1
        add r0, $1              @ 2's compliment
        add r0, zra

        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opR10H:  @0xD7
        add r0, zpc, $3
        bic r0, $0x00FF0000
        bic r0, $0xFF000000

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $32
        mov zpc, $0x10
        b cpu_inst_r

opRETC:  @0xD8
        mov zil, $8

        tst zrf, $flC
        addeq zpc, $1
        beq cpu_inst_r

        mov r0, zsp
        bl mmu_rh

        add zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000

        mov zpc, r1

        b cpu_inst_r

opRETI:  @0xD9
        @ TODO: Enable interrupts

        mov r0, zsp
        bl mmu_rh

        add zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000

        mov zpc, r1

        mov zil, $8
        b cpu_inst_r

opJPCnn: @0xDA
        mov zil, $12

        tst zrf, $flC
        addeq zpc, $3
        beq cpu_inst_r

        bl mmu_rih1
        mov zpc, r1
        b cpu_inst_r

opCCnn:  @0xDC
        mov zil, $12
        add zpc, $3

        tst zrf, $flC
        beq cpu_inst_r

        bl mmu_rih1

        bic r0, zpc, $0x00FF0000
        bic r0, $0xFF000000
        mov zpc, r1

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        b cpu_inst_r

opScAn:  @0xDE
        bl mmu_ri1

        mvn r0, r1
        tst zrf, $flC
        addeq r0, $1            @ 2's compliment
        add r0, zra

        mov zrf, $flN           @ set only subtract

        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zra, r0
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opR18H:  @0xDF
        add r0, zpc, $3
        bic r0, $0x00FF0000
        bic r0, $0xFF000000

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $32
        mov zpc, $0x18
        b cpu_inst_r

opLDFnA: @0xE0
        bl mmu_ri1
        orr r1, $0xFF00
        orr r0, zra, r1, lsl $0x10
        bl mmu_wb

        mov zil, $12
        add zpc, $2
        b cpu_inst_r

opPOPHL: @0xE1
        mov r0, zsp
        add zsp, $2
        bl mmu_rh
        and zrh, r1, $0xFF
        lsr zrl, r1, $0x08

        mov zil, $12
        add zpc, $1
        b cpu_inst_r

opLDFCA: @0xE2
        orr r0, zrc, $0xFF00
        orr r0, zra, r0, lsl $0x10
        bl mmu_wb

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opPUSHL: @0xE5
        sub zsp, $2
        orr r0, zrl, zrh, lsl $0x08
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $16
        add zpc, $1
        b cpu_inst_r

opANAn:  @0xE6
        bl mmu_ri1

        mov zrf, $flH           @ set only half-carry

        ands zra, r1
        orreq zrf, $flZ                 @ set zero

        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opR20H:  @0xE7
        add r0, zpc, $3
        bic r0, $0x00FF0000
        bic r0, $0xFF000000

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $32
        mov zpc, $0x20
        b cpu_inst_r

opASPn:  @0xE8
        bl mmu_ri1

        add r0, r1, zsp

        eor zrf, zrf            @ reset all flags

        eor r1, r1, zsp
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        lsl r0, $10
        lsrs zsp, r0, $10               @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zil, $16
        add zpc, $2
        b cpu_inst_r

opJPHL:  @0xE9
        orr zpc, zrl, zrh, lsl $0x08

        mov zil, $4
        b cpu_inst_r

opLDnnA: @0xEA
        bl mmu_rih1
        orr r0, zra, r1, lsl $0x10
        bl mmu_wb

        add zil, $16
        add zpc, $3
        b cpu_inst_r

opXOAn:  @0xEE
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        eors zra, r1
        orreq zrf, $flZ                 @ set zero

        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opR28H:  @0xEF
        add r0, zpc, $3
        bic r0, $0x00FF0000
        bic r0, $0xFF000000

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $32
        mov zpc, $0x28
        b cpu_inst_r

opLDAFn: @0xF0
        bl mmu_ri1
        orr r0, r1, $0xFF00
        bl mmu_rb

        mov zra, r1
        mov zil, $12
        add zpc, $2
        b cpu_inst_r

opPOPAF: @0xF1
        mov r0, zsp
        add zsp, $2
        bl mmu_rh
        and zra, r1, $0xFF
        lsr zrf, r1, $0x08

        mov zil, $12
        add zpc, $1
        b cpu_inst_r

opLDAFC: @0xF2
        orr r0, zrc, $0xFF00
        bl mmu_rb

        mov zra, r1
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opDI:    @0xF3
        @ TODO: Disable interrupts

        add zil, $4
        add zpc, $1
        b cpu_inst_r

opPUSAF: @0xF5
        sub zsp, $2
        orr r0, zrf, zra, lsl $0x08
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $16
        add zpc, $1
        b cpu_inst_r

opORAn:  @0xF6
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        orrs zra, r1
        orreq zrf, $flZ                 @ set zero

        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opR30H:  @0xF7
        add r0, zpc, $3
        bic r0, $0x00FF0000
        bic r0, $0xFF000000

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $32
        mov zpc, $0x30
        b cpu_inst_r

opLDHLSn:@0xF8
        @ NOTE: The docs are pretty unclear on the flags here.
        @ I'm guessing it is treated like a typical 16-bit add.

        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        add r0, r1, zsp

        eor r1, r1, zsp
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x1000         @ if bit 12 is set
        orrne zrf, $flH                 @ set half-carry

        tst r0, $0x10000        @ if bit 16 is set
        orrne zrf, $flC                 @ set full-carry

        and zrl, r0, $0xFF
        lsr zrh, r0, $0x08
        and zrh, $0xFF                  @ clear any carried bit(s)

        mov zil, $12
        add zpc, $2
        b cpu_inst_r

opLDSHL: @0xF9
        mov sp, zrl
        orr sp, zrh, lsl $0x08

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDAnn: @0xFA
        bl mmu_rih1
        mov r0, r1
        bl mmu_rb

        mov zra, r1
        add zil, $16
        add zpc, $3
        b cpu_inst_r

opEI:    @0xFB
        @ TODO: Enable interrupts

        add zil, $4
        add zpc, $1
        b cpu_inst_r

opEXIT:  @0xFD
        mov r0, zra
        add zpc, $1

        /* MOVING BACK TO SYS */

        ldr r1, =Z80RS
        stmea r1, {r2-r14}

        ldr r0, =SYSRS_E
        ldmea r0, {r4-r13, pc}

opCAn:   @0xFE
        bl mmu_ri1

        mov zrf, $flN           @ set only subtract

        mvn r0, r1
        add r0, $1              @ 2's compliment
        add r0, zra

        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry

        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        ands r0, $0xFF                  @ clear any carried bit(s)
        orreq zrf, $flZ                 @ set zero

        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opR38H:  @0xFF
        add r0, zpc, $3
        bic r0, $0x00FF0000
        bic r0, $0xFF000000

        sub zsp, $2
        bic zsp, $0x00FF0000
        bic zsp, $0xFF000000
        orr r0, r0, zsp, lsl $0x10
        bl mmu_wh

        mov zil, $32
        mov zpc, $0x38
        b cpu_inst_r
