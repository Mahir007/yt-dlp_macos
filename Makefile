# `make test ZSH=/path/to/zsh` tests with another zsh.
ZSH ?= /bin/zsh
BATS := test/bats/bin/bats

.PHONY: test lint

test: $(BATS)
	TEST_ZSH=$(ZSH) $(BATS) test

lint:
	$(ZSH) -n src/setup-yt-dlp.zsh
	shellcheck test/test_helper/common.bash test/*.bats test/fakes/*

$(BATS):
	@echo "The test submodules are missing. Run: git submodule update --init" >&2
	@exit 1
