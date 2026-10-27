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

# package TAG: build the archive for TAG into $BATS_TEST_TMPDIR/dist.
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

@test "the archive holds the script and the license" {
    needs_gnu_tar
    run -0 package v1.2.3-beta.4
    run -0 tar -tvJf "$BATS_TEST_TMPDIR/dist/setup-yt-dlp.tar.xz"
    assert_line --regexp "^drwxr-xr-x 0/0 .* setup-yt-dlp-1\.2\.3-beta\.4/$"
    assert_line --regexp "^-rw-r--r-- 0/0 .* setup-yt-dlp-1\.2\.3-beta\.4/LICENSE$"
    assert_line --regexp "^-rwxr-xr-x 0/0 .* setup-yt-dlp-1\.2\.3-beta\.4/setup-yt-dlp\.zsh$"
    assert_equal "${#lines[@]}" 3
    cd "$BATS_TEST_TMPDIR/dist"
    run -0 sha256sum -c setup-yt-dlp.tar.xz.sha256
}

@test "the packaged script has the tag's version" {
    needs_gnu_tar
    run -0 package v1.2.3-beta.4
    tar -xJf "$BATS_TEST_TMPDIR/dist/setup-yt-dlp.tar.xz" -C "$BATS_TEST_TMPDIR"
    run -0 "$ZSH_BIN" "$BATS_TEST_TMPDIR/setup-yt-dlp-1.2.3-beta.4/setup-yt-dlp.zsh" --version
    assert_output 'setup-yt-dlp 1.2.3-beta.4'
    # The version is all that differs from the script in the repository.
    run -1 diff "$ROOT/src/setup-yt-dlp.zsh" "$BATS_TEST_TMPDIR/setup-yt-dlp-1.2.3-beta.4/setup-yt-dlp.zsh"
    assert_output --regexp '^[0-9]+c[0-9]+
< typeset -gr SETUP_VERSION=0.0.0-dev
---
> typeset -gr SETUP_VERSION=1\.2\.3-beta\.4$'
}

@test "the same commit gives the same archive" {
    needs_gnu_tar
    run -0 package v1.2.3
    mv "$BATS_TEST_TMPDIR/dist" "$BATS_TEST_TMPDIR/first"
    run -0 package v1.2.3
    run -0 cmp "$BATS_TEST_TMPDIR/first/setup-yt-dlp.tar.xz" "$BATS_TEST_TMPDIR/dist/setup-yt-dlp.tar.xz"
}

@test "a tag that isn't a version is refused" {
    local tag
    for tag in 1.2.3 v1.2 vnext v1.2.3/x; do
        run -1 --separate-stderr package "$tag"
        assert_stderr "error: $tag isn't a version tag, such as v1.0.0 or v1.0.0-beta.1"
    done
    assert [ ! -e "$BATS_TEST_TMPDIR/dist" ]
}

@test "the notes group the commits since the last release" {
    git init -q "$BATS_TEST_TMPDIR/repo"
    cd "$BATS_TEST_TMPDIR/repo"
    commit "Add the first thing" src/a
    git tag v0.1.0
    commit "Add a second thing" src/a
    commit "Fix the first thing" src/a
    commit "Tidy the wording" src/b
    commit "Rename a thing" src/c
    git revert --no-edit HEAD >/dev/null
    commit "Test the second thing" test/a.bats
    git tag v0.2.0-beta.1
    printf '%s  setup-yt-dlp.tar.xz\n' 0123abcd >"$BATS_TEST_TMPDIR/sums"

    run -0 "$ROOT/.github/scripts/release-notes.sh" v0.2.0-beta.1 me/repo "$BATS_TEST_TMPDIR/sums"
    assert_line --index 0 '> [!WARNING]'
    assert_line --index 1 '> This is a pre-release, for trying things out before 0.2.0 is final.'
    assert_line 'curl -fsSLO https://github.com/me/repo/releases/download/v0.2.0-beta.1/setup-yt-dlp.tar.xz'
    assert_line './setup-yt-dlp-0.2.0-beta.1/setup-yt-dlp.zsh'
    assert_output --regexp '### ✨ New

- Add a second thing \([0-9a-f]+\)

### 🐛 Fixes

- Fix the first thing \([0-9a-f]+\)

### 🔧 Changes

- Tidy the wording \([0-9a-f]+\)

<details>
<summary>🧰 Tests, CI and other development \(1\)</summary>

- Test the second thing \([0-9a-f]+\)'
    refute_output --partial 'Add the first thing'
    refute_output --partial 'Rename a thing'
    assert_line '**Full changelog:** [v0.1.0...v0.2.0-beta.1](https://github.com/me/repo/compare/v0.1.0...v0.2.0-beta.1)'
    assert_line '0123abcd  setup-yt-dlp.tar.xz'
}

@test "the notes for a final release have no pre-release warning" {
    git init -q "$BATS_TEST_TMPDIR/repo"
    cd "$BATS_TEST_TMPDIR/repo"
    commit "Add the first thing" src/a
    git tag v1.0.0
    : >"$BATS_TEST_TMPDIR/sums"
    run -0 "$ROOT/.github/scripts/release-notes.sh" v1.0.0 me/repo "$BATS_TEST_TMPDIR/sums"
    refute_output --partial 'pre-release'
    assert_line '**Full changelog:** [all commits](https://github.com/me/repo/commits/v1.0.0)'
}
