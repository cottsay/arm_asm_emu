CROSS=
AS=$(CROSS)as
AR=$(CROSS)ar
LD=$(CROSS)ld

ASFLAGS=-g

SRCDIR=src
OBJDIR=obj
BINDIR=bin
LIBDIR=lib

all: $(LIBDIR)/emu.a $(BINDIR)/start

$(OBJDIR)/cpu.o: $(SRCDIR)/cpu.S | $(OBJDIR)
	$(AS) $(ASFLAGS) -o $@ $^

$(OBJDIR)/mmu.o: $(SRCDIR)/mmu.S | $(OBJDIR)
	$(AS) $(ASFLAGS) -o $@ $^

$(OBJDIR)/start.o: $(SRCDIR)/start.S | $(OBJDIR)
	$(AS) $(ASFLAGS) -o $@ $^

$(LIBDIR)/emu.a: $(OBJDIR)/cpu.o $(OBJDIR)/mmu.o | $(LIBDIR)
	$(AR) rcs $@ $^

$(BINDIR)/start: $(OBJDIR)/start.o $(LIBDIR)/emu.a | $(BINDIR)
	$(LD) -o $@ $^

$(OBJDIR):
	mkdir $(OBJDIR)
$(LIBDIR):
	mkdir $(LIBDIR)
$(BINDIR):
	mkdir $(BINDIR)

clean:
	rm -rf $(OBJDIR) $(LIBDIR) $(BINDIR)
