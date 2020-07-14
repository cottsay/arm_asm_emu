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

BASE_OBJS=cpu dispatch gpu mmu stat terminal time timer
OBJS=$(BASE_OBJS)

ifdef NULL_GRAPHICS
OBJS+=display_null screen_null
else
OBJS+=fbdev framebuffer
endif

ifdef NULL_INPUT
OBJS+=input_null
else
OBJS+=evdev
endif

ifdef EMBED_BIOS
ASFLAGS+=--defsym EMBED_BIOS=1
endif

all: $(LIBDIR)/emu.a $(BINDIR)/start

$(OBJDIR)/%.o: $(SRCDIR)/%.S | $(OBJDIR)
	$(AS) $(ASFLAGS) -o$@ $^

$(LIBDIR)/emu.a: $(foreach V,$(OBJS),$(OBJDIR)/$(V).o) | $(LIBDIR)
	$(AR) rcs $@ $^

$(BINDIR)/start: $(OBJDIR)/start.o $(LIBDIR)/emu.a | $(BINDIR)
	$(LD) $(LDFLAGS) -o$@ $^

$(BINDIR)/test_harness: $(OBJDIR)/test_harness.o $(foreach V,$(BASE_OBJS),$(OBJDIR)/$(V).o) $(OBJDIR)/input_null.o $(OBJDIR)/bitmap.o $(OBJDIR)/framebuffer.o $(OBJDIR)/crc32.o | $(BINDIR)
	$(LD) $(LDFLAGS) -o$@ $^

$(OBJDIR):
	mkdir $(OBJDIR)
$(LIBDIR):
	mkdir $(LIBDIR)
$(BINDIR):
	mkdir $(BINDIR)

test: $(BINDIR)/test_harness

clean:
	rm -rf $(OBJDIR) $(LIBDIR) $(BINDIR)
