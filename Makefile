# distrofetch — development and packaging targets.
#
# There is nothing to compile; `dist` builds a release tarball and `install` places
# the script and its libraries under PREFIX.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

PREFIX  ?= /usr/local
DESTDIR ?=
VERSION := $(shell sed -n 's/^DISTROFETCH_VERSION="\(.*\)"$$/\1/p' bin/distrofetch)

BINDIR := $(DESTDIR)$(PREFIX)/bin
LIBDIR := $(DESTDIR)$(PREFIX)/lib/distrofetch

SCRIPTS := bin/distrofetch lib/detect.sh lib/render.sh scripts/banner.sh
SHFMT_FLAGS := -i 2 -ci -bn

.DEFAULT_GOAL := help
.PHONY: help check-tools lint fmt fmt-check test smoke dist install uninstall clean version

help: ## Show this help
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  %-12s %s\n", $$1, $$2}'

check-tools: ## Verify the development tools are installed
	@missing=0; \
	for t in shellcheck shfmt bats; do \
		command -v "$$t" >/dev/null 2>&1 || { echo "missing: $$t" >&2; missing=1; }; \
	done; \
	if [ "$$missing" -ne 0 ]; then \
		echo "install them with your package manager, then re-run" >&2; \
		exit 1; \
	fi; \
	echo "all development tools present"

lint: ## Run shellcheck
	shellcheck -x $(SCRIPTS)

fmt: ## Rewrite scripts with shfmt
	shfmt -w $(SHFMT_FLAGS) $(SCRIPTS)

fmt-check: ## Fail if anything is unformatted
	shfmt -d $(SHFMT_FLAGS) $(SCRIPTS)

test: ## Run the bats suite
	bats --print-output-on-failure tests/

smoke: ## Run the real entry point against this machine
	bin/distrofetch --no-color

version: ## Print the version bin/distrofetch reports
	@echo $(VERSION)

dist: ## Build dist/distrofetch-$(VERSION).tar.gz and its checksum
	rm -rf dist
	mkdir -p dist/distrofetch-$(VERSION)
	cp -r bin lib Makefile README.md LICENSE dist/distrofetch-$(VERSION)/
	tar -C dist -czf dist/distrofetch-$(VERSION).tar.gz distrofetch-$(VERSION)
	rm -rf dist/distrofetch-$(VERSION)
	cd dist && sha256sum distrofetch-$(VERSION).tar.gz > distrofetch-$(VERSION).tar.gz.sha256

install: ## Install to PREFIX (default /usr/local)
	install -Dm755 bin/distrofetch $(BINDIR)/distrofetch
	install -Dm644 lib/detect.sh $(LIBDIR)/detect.sh
	install -Dm644 lib/render.sh $(LIBDIR)/render.sh

uninstall: ## Remove an installed copy
	rm -f $(BINDIR)/distrofetch
	rm -rf $(LIBDIR)

clean: ## Remove build output
	rm -rf dist
