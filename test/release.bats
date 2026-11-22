#!/usr/bin/env bats
# The release archive and notes, from .github/scripts.

setup() {
    load test_helper/common
    common_setup
    ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
    export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
}

teardown() {
    common_teardown
}

# package VERSION: build the archives for VERSION into $BATS_TEST_TMPDIR/dist.
package() {
    (cd "$ROOT" && .github/scripts/package.sh "$1" "$BATS_TEST_TMPDIR/dist")
}

needs_gnu_tar() {
    tar --version 2>/dev/null | grep -q 'GNU tar' || skip "packaging needs GNU tar, as on the release runner"
}

# commit SUBJECT FILE: commit a change to FILE in the current repo.
commit() {
    mkdir -p "$(dirname "$2")"
    echo "$1" >>"$2"
    git add "$2"
    git commit -q -m "$1"
}

@test "the archive holds the script and the license, with no folder" {
    needs_gnu_tar
    run -0 package 1.2.3-beta.4
    run -0 tar -tvJf "$BATS_TEST_TMPDIR/dist/setup-yt-dlp.tar.xz"
    assert_line --regexp "^-rw-r--r-- 0/0 .* LICENSE$"
    assert_line --regexp "^-rwxr-xr-x 0/0 .* setup-yt-dlp\.zsh$"
    assert_equal "${#lines[@]}" 2
    cd "$BATS_TEST_TMPDIR/dist"
    run -0 sha256sum -c setup-yt-dlp.tar.xz.sha256
}

@test "the packaged script has the version" {
    needs_gnu_tar
    run -0 package 1.2.3-beta.4
    tar -xJf "$BATS_TEST_TMPDIR/dist/setup-yt-dlp.tar.xz" -C "$BATS_TEST_TMPDIR"
    run -0 "$ZSH_BIN" "$BATS_TEST_TMPDIR/setup-yt-dlp.zsh" --version
    assert_output 'setup-yt-dlp 1.2.3-beta.4'
    # The version is all that differs from the script in the repository.
    run -1 diff "$ROOT/src/setup-yt-dlp.zsh" "$BATS_TEST_TMPDIR/setup-yt-dlp.zsh"
    assert_output --regexp '^[0-9]+c[0-9]+
< typeset -gr SETUP_VERSION=0.0.0-dev
---
> typeset -gr SETUP_VERSION=1\.2\.3-beta\.4$'
}

@test "the standalone archive holds its script, with the version, and the license" {
    needs_gnu_tar
    run -0 package 1.2.3-beta.4
    run -0 tar -tvJf "$BATS_TEST_TMPDIR/dist/setup-yt-dlp-standalone.tar.xz"
    assert_line --regexp "^-rw-r--r-- 0/0 .* LICENSE$"
    assert_line --regexp "^-rwxr-xr-x 0/0 .* setup-yt-dlp-standalone\.zsh$"
    assert_equal "${#lines[@]}" 2
    tar -xJf "$BATS_TEST_TMPDIR/dist/setup-yt-dlp-standalone.tar.xz" -C "$BATS_TEST_TMPDIR"
    run -0 "$ZSH_BIN" "$BATS_TEST_TMPDIR/setup-yt-dlp-standalone.zsh" --version
    assert_output 'setup-yt-dlp-standalone 1.2.3-beta.4'
    cd "$BATS_TEST_TMPDIR/dist"
    run -0 sha256sum -c setup-yt-dlp-standalone.tar.xz.sha256
}

@test "the same commit gives the same archive" {
    needs_gnu_tar
    run -0 package 1.2.3
    mv "$BATS_TEST_TMPDIR/dist" "$BATS_TEST_TMPDIR/first"
    run -0 package 1.2.3
    run -0 cmp "$BATS_TEST_TMPDIR/first/setup-yt-dlp.tar.xz" "$BATS_TEST_TMPDIR/dist/setup-yt-dlp.tar.xz"
    run -0 cmp "$BATS_TEST_TMPDIR/first/setup-yt-dlp-standalone.tar.xz" "$BATS_TEST_TMPDIR/dist/setup-yt-dlp-standalone.tar.xz"
}

@test "a CI build has the commit in its version" {
    needs_gnu_tar
    run -0 package 0.0.0-dev+1a2b3c4
    tar -xJf "$BATS_TEST_TMPDIR/dist/setup-yt-dlp.tar.xz" -C "$BATS_TEST_TMPDIR"
    run -0 "$ZSH_BIN" "$BATS_TEST_TMPDIR/setup-yt-dlp.zsh" --version
    assert_output 'setup-yt-dlp 0.0.0-dev+1a2b3c4'
}

@test "a version that isn't one is refused" {
    local version
    for version in v1.2.3 1.2 next 1.2.3/x; do
        run -1 --separate-stderr package "$version"
        assert_stderr "error: $version isn't a version, such as 1.0.0, 1.0.0-beta.1 or 0.0.0-dev+1a2b3c4"
    done
}

# The link after each commit in the notes, as a regular expression. The
# backticks are part of the Markdown.
# shellcheck disable=SC2016
link='\(\[`[0-9a-f]{7}`\]\(https://github\.com/me/repo/commit/[0-9a-f]{40}\)\)'

@test "the notes group the commits since the last release by type" {
    git init -q "$BATS_TEST_TMPDIR/repo"
    cd "$BATS_TEST_TMPDIR/repo"
    commit "feat: add the first thing" src/a
    git tag v0.1.0
    commit "feat: add a second thing" src/a
    commit "fix(setup): mend the first thing" src/a
    commit "perf: start faster" src/a
    commit "docs: explain a thing" README.md
    commit "docs(contributing): explain the tests" CONTRIBUTING.md
    commit "refactor: rename a thing" src/c
    git revert --no-edit HEAD >/dev/null
    commit "test: test the second thing" test/a.bats
    git tag v0.2.0-beta.1
    printf '%s  setup-yt-dlp.tar.xz\n' 0123abcd >"$BATS_TEST_TMPDIR/sums"
    printf '%s  setup-yt-dlp-standalone.tar.xz\n' 4567ef01 >"$BATS_TEST_TMPDIR/standalone-sums"

    run -0 "$ROOT/.github/scripts/release-notes.sh" v0.2.0-beta.1 me/repo "$BATS_TEST_TMPDIR/sums" "$BATS_TEST_TMPDIR/standalone-sums"
    assert_line --index 0 '> [!WARNING]'
    assert_line --index 1 '> This is a pre-release, for trying things out before 0.2.0 is final.'
    assert_line 'curl -fsSLO https://github.com/me/repo/releases/download/v0.2.0-beta.1/setup-yt-dlp.tar.xz'
    assert_line './setup-yt-dlp.zsh'
    assert_line 'curl -fsSLO https://github.com/me/repo/releases/download/v0.2.0-beta.1/setup-yt-dlp-standalone.tar.xz'
    assert_line './setup-yt-dlp-standalone.zsh'
    assert_output --regexp "### ✨ Features

- Add a second thing $link

### 🐛 Fixes

- \*\*setup:\*\* Mend the first thing $link

### ⚡ Performance

- Start faster $link

### 📖 Documentation

- Explain a thing $link

<details>
<summary>🧰 Other changes \(2\)</summary>

- docs\(contributing\): explain the tests $link
- test: test the second thing $link
"
    refute_output --partial 'add the first thing'
    refute_output --partial 'rename a thing'
    refute_output --partial 'No user-facing changes'
    assert_line '**Full changelog:** [v0.1.0...v0.2.0-beta.1](https://github.com/me/repo/compare/v0.1.0...v0.2.0-beta.1)'
    assert_line '0123abcd  setup-yt-dlp.tar.xz'
    assert_line '4567ef01  setup-yt-dlp-standalone.tar.xz'
}

@test "the notes list a breaking change once, with its footer" {
    git init -q "$BATS_TEST_TMPDIR/repo"
    cd "$BATS_TEST_TMPDIR/repo"
    commit "feat(setup)!: drop --output

Why.

BREAKING CHANGE: Pass the folder
after --downloader instead.
Co-Authored-By: Someone <a@b.c>" src/a
    commit "fix!: keep the log" src/a
    git tag v1.0.0
    : >"$BATS_TEST_TMPDIR/sums"

    run -0 "$ROOT/.github/scripts/release-notes.sh" v1.0.0 me/repo "$BATS_TEST_TMPDIR/sums"
    assert_output --regexp "### ⚠️ Breaking changes

- \*\*setup:\*\* Drop --output\. Pass the folder after --downloader instead\. $link
- Keep the log $link
"
    refute_output --partial '### ✨ Features'
    refute_output --partial '### 🐛 Fixes'
}

@test "the notes say when nothing users see has changed" {
    git init -q "$BATS_TEST_TMPDIR/repo"
    cd "$BATS_TEST_TMPDIR/repo"
    commit "ci: run the tests" .github/workflows/ci.yml
    git tag v1.0.0
    commit "Tidy the scripts" src/a
    git tag v1.0.1
    : >"$BATS_TEST_TMPDIR/sums"

    run -0 "$ROOT/.github/scripts/release-notes.sh" v1.0.0 me/repo "$BATS_TEST_TMPDIR/sums"
    assert_line 'No user-facing changes.'
    # A commit without a type may still change the scripts.
    run -0 "$ROOT/.github/scripts/release-notes.sh" v1.0.1 me/repo "$BATS_TEST_TMPDIR/sums"
    refute_output --partial 'No user-facing changes'
    assert_line --regexp "^- Tidy the scripts $link\$"
}

@test "the notes for a final release have no pre-release warning" {
    git init -q "$BATS_TEST_TMPDIR/repo"
    cd "$BATS_TEST_TMPDIR/repo"
    commit "feat: add the first thing" src/a
    git tag v1.0.0
    : >"$BATS_TEST_TMPDIR/sums"
    run -0 "$ROOT/.github/scripts/release-notes.sh" v1.0.0 me/repo "$BATS_TEST_TMPDIR/sums"
    refute_output --partial 'pre-release'
    assert_line '**Full changelog:** [all commits](https://github.com/me/repo/commits/v1.0.0)'
}

@test "the notes for a final release list everything since the last final release" {
    git init -q "$BATS_TEST_TMPDIR/repo"
    cd "$BATS_TEST_TMPDIR/repo"
    commit "feat: add the first thing" src/a
    git tag v1.0.0-beta.1
    commit "feat: add a second thing" src/a
    git tag v1.0.0
    commit "feat: add a third thing" src/a
    git tag v1.1.0-beta.1
    commit "feat: add a fourth thing" src/a
    git tag v1.1.0
    : >"$BATS_TEST_TMPDIR/sums"

    run -0 "$ROOT/.github/scripts/release-notes.sh" v1.0.0 me/repo "$BATS_TEST_TMPDIR/sums"
    assert_output --regexp "- Add the first thing $link
- Add a second thing $link"
    assert_line '**Full changelog:** [all commits](https://github.com/me/repo/commits/v1.0.0)'

    run -0 "$ROOT/.github/scripts/release-notes.sh" v1.1.0 me/repo "$BATS_TEST_TMPDIR/sums"
    refute_output --partial 'Add a second thing'
    assert_output --regexp "- Add a third thing $link
- Add a fourth thing $link"
    assert_line '**Full changelog:** [v1.0.0...v1.1.0](https://github.com/me/repo/compare/v1.0.0...v1.1.0)'

    # A pre-release still lists only what's new since the tag before it.
    run -0 "$ROOT/.github/scripts/release-notes.sh" v1.1.0-beta.1 me/repo "$BATS_TEST_TMPDIR/sums"
    refute_output --partial 'Add a second thing'
    assert_line '**Full changelog:** [v1.0.0...v1.1.0-beta.1](https://github.com/me/repo/compare/v1.0.0...v1.1.0-beta.1)'
}
