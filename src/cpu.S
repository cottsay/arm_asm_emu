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
 * and more so interpretation.
 *
 * Please note that internally, EABI calling conventions are not used!
 *
 * The layout of the system is as follows:
 * | Z80 Entity | RasPi Entity |
 * | ---------- | ------------ |
 * | scratch    | r0           |
 * | scratch    | r1           |
 * | funcs      | r2           |
 * | ra         | r3           |
 * | rb         | r4           |
 * | rc         | r5           |
 * | rd         | r6           |
 * | re         | r7           |
 * | rf         | r8           |
 * | rh         | r9           |
 * | rl         | r10          |
 * | pc         | r11          |
 * | il         | r12          |
 * | sp         | r13 (sp)     |
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

        .equ flC, 0x80
        .equ flH, 0x40
        .equ flN, 0x20
        .equ flZ, 0x10

        .data
Z80RS:  .space 40
SYSRS:  .space 56
ZOPS:   .word    opNOP,opLDBCnn, opLDBCA,   0x03,   opIB,   0x05, opLDBn,   0x07
        .word opLDnnSP,    0x09, opLDABC,   0x0B,   opIC,   0x0D, opLDCn,   0x0F
        .word     0x10,opLDDEnn, opLDDEA,   0x13,   opID,   0x15, opLDDn,   0x17
        .word     0x18,    0x19, opLDADE,   0x1B,   opIE,   0x1D, opLDEn,   0x1F
        .word     0x20,opLDHLnn,opLDHLiA,   0x23,   opIH,   0x25, opLDHn,   0x27
        .word     0x28,    0x29,opLDAHLi,   0x2B,   opIL,   0x2D, opLDLn,   0x2F
        .word     0x30,opLDSPnn,opLDHLdA,   0x00,  opIHL,   0x00,   0x00,   0x00
        .word     0x38,    0x00,opLDAHLd,   0x00,   opIA,   0x00, opLDAn,   0x00
        .word   opLDBB,  opLDBC,  opLDBD, opLDBE, opLDBH, opLDBL,opLDBHL, opLDBA
        .word   opLDCB,  opLDCC,  opLDCD, opLDCE, opLDCH, opLDCL,opLDCHL, opLDCA
        .word   opLDDB,  opLDDC,  opLDDD, opLDDE, opLDDH, opLDDL,opLDDHL, opLDDA
        .word   opLDEB,  opLDEC,  opLDED, opLDEE, opLDEH, opLDEL,opLDEHL, opLDEA
        .word   opLDHB,  opLDHC,  opLDHD, opLDHE, opLDHH, opLDHL,opLDHHL, opLDHA
        .word   opLDLB,  opLDLC,  opLDLD, opLDLE, opLDLH, opLDLL,opLDLHL, opLDLA
        .word  opLDHLB, opLDHLC, opLDHLD,opLDHLE,opLDHLH,opLDHLL,opLDHLn,opLDHLA
        .word   opLDAB,  opLDAC,  opLDAD, opLDAE, opLDAH, opLDAL,opLDAHL, opLDAA
        .word    opAAB,   opAAC,   opAAD,  opAAE,  opAAH,  opAAL, opAAHL,  opAAA
        .word   opAcAB,  opAcAC,  opAcAD, opAcAE, opAcAH, opAcAL,opAcAHL, opAcAA
        .word    opSAB,   opSAC,   opSAD,  opSAE,  opSAH,  opSAL, opSAHL,  opSAA
        .word   opScAB,  opScAC,  opScAD, opScAE, opScAH, opScAL,opScAHL, opScAA
        .word   opANAB,  opANAC,  opANAD, opANAE, opANAH, opANAL,opANAHL, opANAA
        .word   opXOAB,  opXOAC,  opXOAD, opXOAE, opXOAH, opXOAL,opXOAHL, opXOAA
        .word   opORAB,  opORAC,  opORAD, opORAE, opORAH, opORAL,opORAHL, opORAA
        .word    opCAB,   opCAC,   opCAD,  opCAE,  opCAH,  opCAL, opCAHL,  opCAA
        .word     0xC0, opPOPBC,    0x00,   0x00,   0x00,opPUSBC,  opAAn,   0x00
        .word     0xC8,    0x00,    0x00,   0x00,   0x00,   0x00, opAcAn,   0x00
        .word     0xD0, opPOPDE,    0x00,   0x00,   0x00,opPUSDE,  opSAn,   0x00
        .word     0xD8,    0x00,    0x00,   0x00,   0x00,   0x00, opScAn,   0x00
        .word  opLDFnA, opPOPHL, opLDFCA,   0x00,   0x00,opPUSHL, opANAn,   0x00
        .word     0xE8,    0x00, opLDnnA,   0x00,   0x00,   0x00, opXOAn,   0x00
        .word  opLDAFn, opPOPAF, opLDAFC,   0xF3,   0xF4,opPUSAF, opORAn,   0xF7
        .word opLDHLSn, opLDSHL, opLDAnn,   0xFB,   0xFC,  opRET,  opCAn,   0xFF

        .text
        .global cpu_init
cpu_init:
        ldr zop, =ZOPS
        mov zra, $0x0F
        @mov zrb, $0
        @mov zrc, $0
        @mov zrd, $0
        @mov zre, $0
        mov zrf, $0x0F
        @mov zrh, $0
        @mov zrl, $0
        mov zpc, $0
        mov zil, $0
        mov zsp, $0xFF
        mov pc, lr

        .global cpu_dispatch
cpu_dispatch:
        ldr r0, =SYSRS
        stmfd r0, {r4-r14}

        ldr r0, =Z80RS
        ldmfd r0, {r0-r13}

        /* Z80 SYSTEM READY */

        bl cpu_step

        /* MOVING BACK TO SYS */

        ldr r0, =Z80RS
        stmfd r0, {r0-r13}

        ldr r0, =SYSRS
        ldmfd r0, {r4-r13, pc}

        .global cpu_step
        .global mmu_ri_r
cpu_step:
        subs zil, $1
        bpl cpu_step

        /* Load Instruction */
        bl mmu_ri
        ldrls pc, [zop, r1, lsl $2]
cpu_inst_r:
        b cpu_step

        .ltorg    @ keep literal pool close

/* INSTRUCTIONS */
opNOP:   @0x00
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDBCnn:@0x01
        bl mmu_rih1
        and zrc, r1, $0x0F
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

opIB:    @0x04
        eor zrf, zrf            @ reset all flags

        adds r0, zrb, $1

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zrb
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

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

opLDnnSP:@0x08
        bl mmu_rih1
        orr r0, sp, r0, lsl $0x10
        bl mmu_wh
        mov zil, $20
        add zpc, $3
        b cpu_inst_r

opLDABC: @0x0A
        orr r0, zrc, zrb, lsl $0x08
        bl mmu_rb
        mov zra, r1
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opLDCn:  @0x0E
        bl mmu_ri1
        mov zrc, r1
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opLDDEnn:@0x11
        bl mmu_rih1
        and zre, r1, $0x0F
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

opLDDn:  @0x16
        bl mmu_ri1
        mov zrd, r1
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opLDADE: @0x0A
        orr r0, zre, zrd, lsl $0x08
        bl mmu_rb
        mov zra, r1
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIC:    @0x0C
        eor zrf, zrf            @ reset all flags

        adds r0, zrc, $1

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zrc
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zrc, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opID:    @0x14
        eor zrf, zrf            @ reset all flags

        adds r0, zrd, $1

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zrd
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zrd, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opIE:    @0x1C
        eor zrf, zrf            @ reset all flags

        adds r0, zre, $1

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zre
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

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

opLDHLnn:@0x21
        bl mmu_rih1
        and zrl, r1, $0x0F
        lsr zrh, r1, $0x08
        mov zil, $12
        add zpc, $3
        b cpu_inst_r

opLDHLiA:@0x22
        orr r0, zrl, zrh, lsl $8
        orr r0, zra, r0, lsl $16
        bl mmu_rb

        add zrl, $1
        cmp zrl, $0xFF
        movhi zrl, $0x00
        addhi zrh, $1
        cmphi zrh, $0xFF
        movhi zrh, $0x00

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIH:    @0x24
        eor zrf, zrf            @ reset all flags

        adds r0, zrh, $1

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zrh
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

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

opLDAHLi:@0x2A
        orr r0, zrl, zrh, lsl $8
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

opIL:    @0x2C
        eor zrf, zrf            @ reset all flags

        adds r0, zrl, $1

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zrl
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

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

opLDSPnn:@0x31
        bl mmu_rih1
        and sp, r1, $0x0F
        lsl sp, $0x08
        orr sp, r1, lsr $0x08
        mov zil, $12
        add zpc, $3
        b cpu_inst_r

opLDHLdA:@0x32
        orr r0, zrl, zrh, lsl $8
        orr r0, zra, r0, lsl $16
        bl mmu_wb

        subs zrl, $1
        movmi zrl, $0xFF
        submis zrh, $1
        movmi zrh, $0xFF

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIHL:  @0x34
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        adds r0, r1, $1

        orreq zrf, $flZ                 @ set zero
        eor r0, r0, r1
        eor r0, r0, $1          @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        orr r0, zrl, zrh, lsl $0x08
        add r1, $1
        orr r0, r1, r0, lsl $16
        bl mmu_wb
        mov zil, $12
        add zpc, $1
        b cpu_inst_r

opLDAHLd:@0x3A
        orr r0, zrl, zrh, lsl $8
        bl mmu_rb
        mov zra, r1

        subs zrl, $1
        movmi zrl, $0xFF
        submis zrh, $1
        movmi zrh, $0xFF

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opIA:    @0x3C
        eor zrf, zrf            @ reset all flags

        adds r0, zra, $1

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, $1          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

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

opLDBB:  @0x40
        mov zrb, zrb
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
        mov zrb, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDBH:  @0x44
        mov zrb, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDBL:  @0x45
        mov zrb, zrd
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
        mov zrc, zrc
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDCD:  @0x4A
        mov zrc, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDCE:  @0x4B
        mov zrc, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDCH:  @0x4C
        mov zrc, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDCL:  @0x4D
        mov zrc, zrd
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
        mov zrd, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDDE:  @0x53
        mov zrd, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDDH:  @0x54
        mov zrd, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDDL:  @0x55
        mov zrd, zrd
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
        mov zre, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDEH:  @0x5C
        mov zre, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDEL:  @0x5D
        mov zre, zrd
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
        mov zrh, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDHH:  @0x64
        mov zrh, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDHL:  @0x65
        mov zrh, zrd
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
        mov zrl, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDLH:  @0x6C
        mov zrl, zrd
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opLDLL:  @0x6D
        mov zrl, zrd
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

opLDHLn: @0x76
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_ri1
        orr r0, r1, r0, lsl $0x10
        bl mmu_wb
        mov zil, $8
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
        mov zra, zra
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAAB:   @0x80
        eor zrf, zrf            @ reset all flags

        adds r0, zra, zrb

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, zrb         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAAC:   @0x81
        eor zrf, zrf            @ reset all flags

        adds r0, zra, zrc

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, zrc         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAAD:   @0x82
        eor zrf, zrf            @ reset all flags

        adds r0, zra, zrd

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, zrd         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAAE:   @0x83
        eor zrf, zrf            @ reset all flags

        adds r0, zra, zre

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, zre         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAAH:   @0x84
        eor zrf, zrf            @ reset all flags

        adds r0, zra, zrh

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, zrh         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAAL:   @0x85
        eor zrf, zrf            @ reset all flags

        adds r0, zra, zrl

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, zrl         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAAHL:  @0x86
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        eor r0, r0, zra
        eor r0, r0, r1          @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        add zra, r1
        and zra, $0xFF                  @ clear the (possible) carried bit
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opAAA:   @0x87
        eor zrf, zrf            @ reset all flags

        adds zra, zra

        orreq zrf, $flZ                 @ set zero
        tst zra, $0x10          @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne zra, $0xFF                @ clear the carried bit

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opAcAB:  @0x88
        eor zrf, zrf            @ reset all flags

        tst zrf, $flZ
        moveq r0, zrb
        addne r0, zrb, $1
        adds r0, zra

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, zrb         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1

        b cpu_inst_r

opAcAC:  @0x89
        eor zrf, zrf            @ reset all flags

        tst zrf, $flZ
        moveq r0, zrc
        addne r0, zrc, $1
        add r0, zra

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, zrc         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1

        b cpu_inst_r

opAcAD:  @0x8A
        eor zrf, zrf            @ reset all flags

        tst zrf, $flZ
        moveq r0, zrd
        addne r0, zrd, $1
        adds r0, zra

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, zrd         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1

        b cpu_inst_r

opAcAE:  @0x8B
        eor zrf, zrf            @ reset all flags

        tst zrf, $flZ
        moveq r0, zre
        addne r0, zre, $1
        adds r0, zra

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, zre         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1

        b cpu_inst_r

opAcAH:  @0x8C
        eor zrf, zrf            @ reset all flags

        tst zrf, $flZ
        moveq r0, zrh
        addne r0, zrh, $1
        adds r0, zra

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, zrh         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1

        b cpu_inst_r

opAcAL:  @0x8D
        eor zrf, zrf            @ reset all flags

        tst zrf, $flZ
        moveq r0, zrl
        addne r0, zrl, $1
        adds r0, zra

        orreq zrf, $flZ                 @ set zero
        eor r1, r0, zra
        eor r1, r1, zrl         @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1

        b cpu_inst_r

opAcAHL: @0x8E
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        tst zrf, $flZ
        moveq r0, r1
        addne r0, r1, $1
        adds r0, zra

        orreq zrf, $flZ                 @ set zero
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $8
        add zpc, $1

        b cpu_inst_r

opAcAA:  @0x8F
        eor zrf, zrf            @ reset all flags

        add zra, zra

        orreq zrf, $flZ                 @ set zero
        tst zra, $0x10          @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst zra, $0x100         @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zil, $4
        add zpc, $1

        tst zrf, $flC
        beq cpu_inst_r

        adds zra, $1             @ it is impossible for a carry here
        orreq zrf, $flZ                 @ set zero
        b cpu_inst_r

opSAB:   @0x90
        eor zrf, zrf            @ reset all flags

        mvn r1, zrb
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opSAC:   @0x91
        eor zrf, zrf            @ reset all flags

        mvn r1, zrc
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opSAD:   @0x92
        eor zrf, zrf            @ reset all flags

        mvn r1, zrd
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opSAE:   @0x93
        eor zrf, zrf            @ reset all flags

        mvn r1, zre
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opSAH:   @0x94
        eor zrf, zrf            @ reset all flags

        mvn r1, zrh
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opSAL:   @0x95
        eor zrf, zrf            @ reset all flags

        mvn r1, zrl
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opSAHL:  @0x96
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        mvn r1, r1
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opSAA:   @0x97
        eor zrf, zrf            @ reset all flags

        mvn r1, zra
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opScAB:  @0x98
        eor zrf, zrf            @ reset all flags

        mvn r1, zrb
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opScAC:  @0x99
        eor zrf, zrf            @ reset all flags

        mvn r1, zrc
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opScAD:  @0x9A
        eor zrf, zrf            @ reset all flags

        mvn r1, zrd
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opScAE:  @0x9B
        eor zrf, zrf            @ reset all flags

        mvn r1, zre
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opScAH:  @0x9C
        eor zrf, zrf            @ reset all flags

        mvn r1, zrh
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opScAL:  @0x9D
        eor zrf, zrf            @ reset all flags

        mvn r1, zrl
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opScAHL:  @0x9E
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        mvn r1, r1
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opScAA:  @0x9F
        eor zrf, zrf            @ reset all flags

        mvn r1, zra
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAB:  @0xA0
        eor zrf, zrf            @ reset all flags

        ands zra, zrb
        orreq zrf, $flZ                 @ set zero
        orr zrf, $flH                   @ set half-carry

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAC:  @0xA1
        eor zrf, zrf            @ reset all flags

        ands zra, zrc
        orreq zrf, $flZ                 @ set zero
        orr zrf, $flH                   @ set half-carry

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAD:  @0xA2
        eor zrf, zrf            @ reset all flags

        ands zra, zrd
        orreq zrf, $flZ                 @ set zero
        orr zrf, $flH                   @ set half-carry

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAE:  @0xA3
        eor zrf, zrf            @ reset all flags

        ands zra, zre
        orreq zrf, $flZ                 @ set zero
        orr zrf, $flH                   @ set half-carry

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAH:  @0xA4
        eor zrf, zrf            @ reset all flags

        ands zra, zrh
        orreq zrf, $flZ                 @ set zero
        orr zrf, $flH                   @ set half-carry

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAL:  @0xA5
        eor zrf, zrf            @ reset all flags

        ands zra, zrl
        orreq zrf, $flZ                 @ set zero
        orr zrf, $flH                   @ set half-carry

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opANAHL: @0xA6
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        ands zra, r1
        orreq zrf, $flZ                 @ set zero
        orr zrf, $flH                   @ set half-carry

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opANAA:  @0xA7
        eor zrf, zrf            @ reset all flags

        ands zra, zra
        orreq zrf, $flZ                 @ set zero
        orr zrf, $flH                   @ set half-carry

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
        eor zrf, zrf            @ reset all flags

        mvn r1, zrb
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opCAC:   @0xB9
        eor zrf, zrf            @ reset all flags

        mvn r1, zrc
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opCAD:   @0xBA
        eor zrf, zrf            @ reset all flags

        mvn r1, zrd
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opCAE:   @0xBB
        eor zrf, zrf            @ reset all flags

        mvn r1, zre
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opCAH:   @0xBC
        eor zrf, zrf            @ reset all flags

        mvn r1, zrh
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opCAL:   @0xBD
        eor zrf, zrf            @ reset all flags

        mvn r1, zrl
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opCAHL:  @0xBE
        orr r0, zrl, zrh, lsl $0x08
        bl mmu_rb

        eor zrf, zrf            @ reset all flags

        mvn r1, r1
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opCAA:   @0xBF
        eor zrf, zrf            @ reset all flags

        mvn r1, zra
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zil, $4
        add zpc, $1
        b cpu_inst_r

opPOPBC: @0xC1
        add sp, $2
        bl mmu_rh
        and zrc, r1, $0x0F
        lsr zrb, r1, $0x08
        mov zil, $12
        add zpc, $1
        b cpu_inst_r

opPUSBC: @0xC5
        sub sp, $2
        orr r0, zrc, zrb, lsl $0x08
        orr r0, r0, sp, lsl $0x10
        bl mmu_wh
        mov zil, $16
        add zpc, $1
        b cpu_inst_r

opAAn:   @0xC6
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        eor r0, r0, zra
        eor r0, r0, r1          @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry

        add zra, r1
        and zra, $0xFF                  @ clear the (possible) carried bit
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opAcAn:   @0xCE
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        tst zrf, $flZ
        moveq r0, r1
        addne r0, r1, $1
        adds r0, zra

        orreq zrf, $flZ                 @ set zero
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $8
        add zpc, $2

        b cpu_inst_r

opPOPDE: @0xD1
        add sp, $2
        bl mmu_rh
        and zre, r1, $0x0F
        lsr zrd, r1, $0x08
        mov zil, $12
        add zpc, $1
        b cpu_inst_r

opPUSDE: @0xD5
        sub sp, $2
        orr r0, zre, zrd, lsl $0x08
        orr r0, r0, sp, lsl $0x10
        bl mmu_wh
        mov zil, $16
        add zpc, $1
        b cpu_inst_r

opSAn:  @0xD6
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        mvn r1, r1
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opScAn:   @0xDE
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        mvn r1, r1
        tst zrf, $flC
        addeq r1, $1            @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zra, r0
        mov zil, $8
        add zpc, $2
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
        add sp, $2
        bl mmu_rh
        and zrl, r1, $0x0F
        lsr zrh, r1, $0x08
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
        sub sp, $2
        orr r0, zrl, zrh, lsl $0x08
        orr r0, r0, sp, lsl $0x10
        bl mmu_wh
        mov zil, $16
        add zpc, $1
        b cpu_inst_r

opANAn:  @0xE6
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        ands zra, r1
        orreq zrf, $flZ                 @ set zero
        orr zrf, $flH                   @ set half-carry

        mov zil, $8
        add zpc, $2
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

opLDAFn: @0xF0
        bl mmu_ri1
        orr r0, r1, $0xFF00
        bl mmu_rb
        mov zra, r1
        mov zil, $12
        add zpc, $2
        b cpu_inst_r

opPOPAF: @0xF1
        add sp, $2
        bl mmu_rh
        and zrf, r1, $0x0F
        lsr zra, r1, $0x08
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

opPUSAF: @0xF5
        sub sp, $2
        orr r0, zrf, zra, lsl $0x08
        orr r0, r0, sp, lsl $0x10
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

opLDHLSn:@0xF8
        bl mmu_ris1             @ r1 is sign extended
        add r0, r1, sp          @ sp is unsigned, of course
        and zrl, r0, $0x0F
        lsr zrh, r0, $0x08

        eor zrf, zrf            @ reset all flags
        eor r0, r0, r1
        eor r0, r0, sp          @ XOR all three
        tst r0, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r0, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne zrh, $0xF                 @ clear the carried bit
        
        mov zil, $12
        add zpc, $2
        b cpu_inst_r

opLDSHL: @0xF9
        and sp, zrl, $0x0F
        lsl sp, $0x08
        orr sp, zrh
        mov zil, $8
        add zpc, $1
        b cpu_inst_r

opRET:   @0xFD
        mov r0, zra
        mov r7, $1
        swi $0

opCAn:  @0xFE
        bl mmu_ri1

        eor zrf, zrf            @ reset all flags

        mvn r1, r1
        add r1, $1              @ 2's compliment
        adds r0, zra, r1

        orreq zrf, $flZ                 @ set zero
        orr zrf, $flN                   @ set subtract
        eor r1, r1, zra
        eor r1, r1, r0          @ XOR all three
        tst r1, $0x10           @ if bit 4 is set
        orrne zrf, $flH                 @ set half-carry
        tst r1, $0x100          @ if bit 8 is set
        orrne zrf, $flC                 @ set full-carry
        andne r0, $0xFF                 @ clear the carried bit

        mov zil, $8
        add zpc, $2
        b cpu_inst_r

opLDAnn: @0xFA
        bl mmu_rih1
        mov r0, r1
        bl mmu_rb
        mov zra, r1
        add zil, $16
        add zpc, $3
        b cpu_inst_r

