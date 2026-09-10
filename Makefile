PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

.PHONY: all build release static install test clean

all: build

build:
	mkdir -p bin
	crystal build src/wgctl.cr -o bin/wgctl

release:
	mkdir -p bin
	crystal build --release --no-debug src/wgctl.cr -o bin/wgctl
	strip -s bin/wgctl

static:
	mkdir -p bin
	crystal build --release --static --no-debug src/wgctl.cr -o bin/wgctl-static
	strip -s bin/wgctl-static

install: release
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 bin/wgctl $(DESTDIR)$(BINDIR)/wgctl

test:
	crystal spec

clean:
	rm -rf bin/
