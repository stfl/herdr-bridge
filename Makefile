PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
ZSHDIR ?= $(PREFIX)/share/zsh/site-functions
BASHDIR ?= $(PREFIX)/share/bash-completion/completions

.PHONY: all test lint fmt install uninstall

all: lint test

test:
	bats test

lint:
	shellcheck --shell=bash bin/herdr-bridge
	shellcheck --shell=bash test/helpers/stub-herdr test/helpers/stub-ssh
	shellcheck --shell=bash completions/herdr-bridge.bash
	bash -n completions/herdr-bridge.bash
	command -v zsh >/dev/null && zsh -n completions/herdr-bridge.zsh || true

fmt:
	shfmt -w -i 2 -ci bin/herdr-bridge

install:
	install -Dm0755 bin/herdr-bridge $(DESTDIR)$(BINDIR)/herdr-bridge
	install -Dm0644 completions/herdr-bridge.zsh $(DESTDIR)$(ZSHDIR)/_herdr-bridge
	install -Dm0644 completions/herdr-bridge.bash $(DESTDIR)$(BASHDIR)/herdr-bridge

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/herdr-bridge
	rm -f $(DESTDIR)$(ZSHDIR)/_herdr-bridge
	rm -f $(DESTDIR)$(BASHDIR)/herdr-bridge
