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
	@if command -v zsh >/dev/null; then zsh -n completions/herdr-bridge.zsh; \
	else echo "zsh not installed; skipping zsh syntax check"; fi

fmt:
	shfmt -w -i 2 -ci bin/herdr-bridge

# install -D is a GNU extension; BSD install, which is what macOS ships, has
# no such flag. Create the directories separately so both work.
install:
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(ZSHDIR) $(DESTDIR)$(BASHDIR)
	install -m 0755 bin/herdr-bridge $(DESTDIR)$(BINDIR)/herdr-bridge
	install -m 0644 completions/herdr-bridge.zsh $(DESTDIR)$(ZSHDIR)/_herdr-bridge
	install -m 0644 completions/herdr-bridge.bash $(DESTDIR)$(BASHDIR)/herdr-bridge

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/herdr-bridge
	rm -f $(DESTDIR)$(ZSHDIR)/_herdr-bridge
	rm -f $(DESTDIR)$(BASHDIR)/herdr-bridge
