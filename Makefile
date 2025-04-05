CC=fpc
CUNIT=./raylib-pas/include/
CLIB=./raylib-pas/lib/
CFLAGS=-Fu$(CUNIT) -Fl$(CLIB) -Px86_64 -g
BUILDDIR=./bin/
SRCSDIR=./src/
SRCS=graphassist
SRCSSUFF=$(addsuffix .exe,$(addprefix $(SRCSDIR),$(SRCS)))

.PHONY: build clean

$(CUNIT)/raylib.ppu:
	$(CC) $(CFLAGS) $(CUNIT)/raylib.pp -o$(BUILDDIR)/raylib.ppu

$(SRCSDIR)%.exe: $(CUNIT)/raylib.ppu
	$(CC) $(CFLAGS) $(SRCSDIR)/$*.pp -o$(BUILDDIR)/$*.exe

build: $(SRCSSUFF)

clean:
	rm -f $(BUILDDIR)/*.exe
	rm -f $(BUILDDIR)/*.o
	rm -f $(BUILDDIR)/*.ppu