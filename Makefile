# `make test ZSH=/path/to/zsh` tests with another zsh.
ZSH ?= /bin/zsh
BATS := test/bats/bin/bats

.PHONY: test test-setup test-standalone lint

test: test-setup test-standalone

test-setup: $(BATS)
	TEST_ZSH=$(ZSH) $(BATS) test

test-standalone: $(BATS)
	TEST_ZSH=$(ZSH) $(BATS) test/standalone

lint:
	$(ZSH) -n src/setup-yt-dlp.zsh
	$(ZSH) -n src/setup-yt-dlp-standalone.zsh
	shellcheck src/youtube-downloader-pro.command test/test_helper/common.bash test/*.bats \
		test/standalone/*.bats test/standalone/helper.bash test/fakes/* .github/scripts/*.sh

$(BATS):
	@echo "The test submodules are missing. Run: git submodule update --init" >&2
	@exit 1
