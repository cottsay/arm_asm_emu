AS=$(CROSS)as
AR=$(CROSS)ar
LD=$(CROSS)ld

SRCDIR:=src
OBJDIR:=obj
BINDIR:=bin
LIBDIR:=lib
INCDIR:=inc

ASFLAGS+=-g --warn --fatal-warnings -I$(INCDIR)
LDFLAGS+=--fatal-warnings

ifdef EMBED_BIOS
ASFLAGS+=--defsym EMBED_BIOS=1
endif

all: $(LIBDIR)/emu.a $(BINDIR)/start

$(OBJDIR)/%.o: $(SRCDIR)/%.S | $(OBJDIR)
	$(AS) $(ASFLAGS) -o$@ $^

$(LIBDIR)/emu.a: $(OBJDIR)/cpu.o $(OBJDIR)/dispatch.o $(OBJDIR)/evdev.o $(OBJDIR)/fbdev.o $(OBJDIR)/framebuffer.o $(OBJDIR)/gpu.o $(OBJDIR)/mmu.o $(OBJDIR)/stat.o $(OBJDIR)/terminal.o $(OBJDIR)/time.o $(OBJDIR)/timer.o | $(LIBDIR)
	$(AR) rcs $@ $^

$(BINDIR)/start: $(OBJDIR)/start.o $(LIBDIR)/emu.a | $(BINDIR)
	$(LD) $(LDFLAGS) -o$@ $^

$(OBJDIR):
	mkdir $(OBJDIR)
$(LIBDIR):
	mkdir $(LIBDIR)
$(BINDIR):
	mkdir $(BINDIR)

clean:
	rm -rf $(OBJDIR) $(LIBDIR) $(BINDIR)
