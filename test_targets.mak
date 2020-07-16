ifdef GB_TEST_ROMS_PATH

TEST_BLARGG_CPU_01=cpu_instrs/individual/01-special.gb            0x00800000 0xA921A164
TEST_BLARGG_CPU_02=cpu_instrs/individual/02-interrupts.gb         0x00700000 0x5E874A18
TEST_BLARGG_CPU_03=cpu_instrs/individual/03-op\ sp,hl.gb          0x00800000 0x3A3C1E64
TEST_BLARGG_CPU_04=cpu_instrs/individual/04-op\ r,imm.gb          0x00900000 0xE0BC40C8
TEST_BLARGG_CPU_05=cpu_instrs/individual/05-op\ rp.gb             0x00A00000 0xD17FB3BF
TEST_BLARGG_CPU_06=cpu_instrs/individual/06-ld\ r,r.gb            0x00700000 0x1D57622D
TEST_BLARGG_CPU_07=cpu_instrs/individual/07-jr,jp,call,ret,rst.gb 0x00700000 0xFFE0197
TEST_BLARGG_CPU_08=cpu_instrs/individual/08-misc\ instrs.gb       0x00700000 0x9408FE48
TEST_BLARGG_CPU_09=cpu_instrs/individual/09-op\ r,r.gb            0x00F00000 0xBE898C8A
TEST_BLARGG_CPU_10=cpu_instrs/individual/10-bit\ ops.gb           0x01400000 0x2D0A6823
TEST_BLARGG_CPU_11=cpu_instrs/individual/11-op\ a,(hl).gb         0x01800000 0xB41CEEDC

TEST_BLARGG_INSTR_TIMING=instr_timing/instr_timing.gb             0x0800000 0x9324CA3F

TEST_BLARGG_MEM_TIMING=mem_timing/mem_timing.gb                   0x0800000 0x632FC879
TEST_BLARGG_MEM_TIMING_2=mem_timing-2/mem_timing.gb               0x0900000 0xAB819285

TEST_BLARGG_OAM_BUG_2=oam_bug/rom_singles/2-causes.gb             0x0800000 0x45087C77
TEST_BLARGG_OAM_BUG_3=oam_bug/rom_singles/3-non_causes.gb         0x0800000 0x4AB5E0C5
TEST_BLARGG_OAM_BUG_5=oam_bug/rom_singles/5-timing_bug.gb         0x0800000 0x452C4F10

define TEST_BLARGG
TEST_TARGETS_BLARGG+=test_blargg__$(subst /,__,$(basename $(wordlist 3,$(words $($T)),1st 2nd $($T))))
test_blargg__$(subst /,__,$(basename $(wordlist 3,$(words $($T)),1st 2nd $($T)))): $(TEST_HARNESS) | $(GB_TEST_ROMS_PATH)/$(wordlist 3,$(words $($T)),1st 2nd $($T))
	@echo "Running Blargg test '$(wordlist 3,$(words $($T)),1st 2nd $($T))'..."
	@$(TEST_WRAPPER) $(TEST_HARNESS) $(GB_TEST_ROMS_PATH)/${subst (,\(,${subst ),\),$($T)}} "test_blargg__$(subst /,__,$(basename $(wordlist 3,$(words $($T)),1st 2nd $($T)))).bmp"
	-@rm -f "test_blargg__$(subst /,__,$(basename $(wordlist 3,$(words $($T)),1st 2nd $($T)))).bmp"
endef

space:=$(eval) $(eval)
$(foreach T,$(filter TEST_BLARGG_%, $(.VARIABLES)),$(eval $(TEST_BLARGG)))
TEST_TARGETS+=$(TEST_TARGETS_BLARGG)

else
TEST_TARGETS+=test_blargg__skip
test_blargg__skip:
	@>&2 echo "GB_TEST_ROMS_PATH was not specified. Skipping Blargg tests."
endif
