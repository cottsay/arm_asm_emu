CROSS=
AS=$(CROSS)as
AR=$(CROSS)ar
LD=$(CROSS)ld

ASFLAGS=-g --warn --fatal-warnings
LDFLAGS=--fatal-warnings

SRCDIR=src
OBJDIR=obj
BINDIR=bin
LIBDIR=lib

all: $(LIBDIR)/emu.a $(BINDIR)/start

$(OBJDIR)/%.o: $(SRCDIR)/%.S | $(OBJDIR)
	$(AS) $(ASFLAGS) -o $@ $^

$(LIBDIR)/emu.a: $(OBJDIR)/cpu.o $(OBJDIR)/mmu.o $(OBJDIR)/stat.o | $(LIBDIR)
	$(AR) rcs $@ $^

$(BINDIR)/start: $(OBJDIR)/start.o $(LIBDIR)/emu.a | $(BINDIR)
	$(LD) $(LDFLAGS) -o $@ $^

$(OBJDIR):
	mkdir $(OBJDIR)
$(LIBDIR):
	mkdir $(LIBDIR)
$(BINDIR):
	mkdir $(BINDIR)

clean:
	rm -rf $(OBJDIR) $(LIBDIR) $(BINDIR)
