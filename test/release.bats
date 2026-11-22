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
    run -0 package 1.2.3-beta.4+1a2b3c4
    run -0 tar -tvJf "$BATS_TEST_TMPDIR/dist/setup-yt-dlp.tar.xz"
    assert_line --regexp "^-rw-r--r-- 0/0 .* LICENSE$"
    assert_line --regexp "^-rwxr-xr-x 0/0 .* setup-yt-dlp\.zsh$"
    assert_equal "${#lines[@]}" 2
    cd "$BATS_TEST_TMPDIR/dist"
    run -0 sha256sum -c setup-yt-dlp.tar.xz.sha256
}

@test "the packaged script has the version" {
    needs_gnu_tar
    run -0 package 1.2.3-beta.4+1a2b3c4
    tar -xJf "$BATS_TEST_TMPDIR/dist/setup-yt-dlp.tar.xz" -C "$BATS_TEST_TMPDIR"
    run -0 "$ZSH_BIN" "$BATS_TEST_TMPDIR/setup-yt-dlp.zsh" --version
    assert_output 'setup-yt-dlp 1.2.3-beta.4+1a2b3c4'
    # The version is all that differs from the script in the repository.
    run -1 diff "$ROOT/src/setup-yt-dlp.zsh" "$BATS_TEST_TMPDIR/setup-yt-dlp.zsh"
    assert_output --regexp '^[0-9]+c[0-9]+
< typeset -gr SETUP_VERSION=0.0.0-dev
---
> typeset -gr SETUP_VERSION=1\.2\.3-beta\.4\+1a2b3c4$'
}

@test "the standalone archive holds its script, with the version, and the license" {
    needs_gnu_tar
    run -0 package 1.2.3-beta.4+1a2b3c4
    run -0 tar -tvJf "$BATS_TEST_TMPDIR/dist/setup-yt-dlp-standalone.tar.xz"
    assert_line --regexp "^-rw-r--r-- 0/0 .* LICENSE$"
    assert_line --regexp "^-rwxr-xr-x 0/0 .* setup-yt-dlp-standalone\.zsh$"
    assert_equal "${#lines[@]}" 2
    tar -xJf "$BATS_TEST_TMPDIR/dist/setup-yt-dlp-standalone.tar.xz" -C "$BATS_TEST_TMPDIR"
    run -0 "$ZSH_BIN" "$BATS_TEST_TMPDIR/setup-yt-dlp-standalone.zsh" --version
    assert_output 'setup-yt-dlp-standalone 1.2.3-beta.4+1a2b3c4'
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
    # A pre-release needs its commit, and only alpha, beta and rc count from 1.
    for version in v1.2.3 1.2 next 1.2.3/x 1.2.3-beta.4 1.2.3-test.1+1a2b3c4 1.2.3-beta.0+1a2b3c4 0.0.0-dev; do
        run -1 --separate-stderr package "$version"
        assert_stderr "error: $version isn't a version, such as 1.0.0, 1.0.0-beta.1+1a2b3c4 or 0.0.0-dev+1a2b3c4"
    done
}

# The link after each commit in the notes, as a regular expression. The
# backticks are part of the Markdown.
# shellcheck disable=SC2016
link='\(\[`[0-9a-f]{7}`\]\(https://github\.com/me/repo/commit/[0-9a-f]{40}\)\)'

# notes TAG SHA256FILE...: write the notes for TAG in the current repo.
notes() {
    "$ROOT/.github/scripts/release-notes.sh" "$1" me/repo "${@:2}"
}

# new_repo: make an empty repo in $BATS_TEST_TMPDIR/repo and go into it.
new_repo() {
    git init -q "$BATS_TEST_TMPDIR/repo"
    cd "$BATS_TEST_TMPDIR/repo" || return
}

@test "the notes have every part, in order" {
    new_repo
    printf '# yt-dlp_macos\n\n## Quick start\n' >README.md
    git add README.md
    git commit -q -m "docs: write the README"
    git tag v1.0.0
    commit "feat(setup): add a thing" src/a
    a=$(git rev-parse HEAD)
    commit "fix!: keep the log

BREAKING CHANGE: Move it to log.txt." src/a
    b=$(git rev-parse HEAD)
    commit "ci: run the tests" .github/workflows/ci.yml
    d=$(git rev-parse HEAD)
    git tag -a -m v1.1.0-beta.1 -m "Adds a thing." v1.1.0-beta.1
    printf '%s  setup-yt-dlp-standalone.tar.xz\n' 4567ef01 >"$BATS_TEST_TMPDIR/standalone-sums"
    printf '%s  setup-yt-dlp.tar.xz\n' 0123abcd >"$BATS_TEST_TMPDIR/sums"

    run -0 notes v1.1.0-beta.1 "$BATS_TEST_TMPDIR/standalone-sums" "$BATS_TEST_TMPDIR/sums"
    expected=$(cat <<'EOF'
> [!WARNING]
> This is a pre-release, for trying things out before 1.1.0 is final. Please report problems in [Issues](https://github.com/me/repo/issues).

Adds a thing.

## Download

| File | For |
| --- | --- |
| [setup-yt-dlp.tar.xz](https://github.com/me/repo/releases/download/v1.1.0-beta.1/setup-yt-dlp.tar.xz) | macOS, with Homebrew or MacPorts |
| [setup-yt-dlp-standalone.tar.xz](https://github.com/me/repo/releases/download/v1.1.0-beta.1/setup-yt-dlp-standalone.tar.xz) | macOS, without a package manager |

For how to install it, see [Quick start](https://github.com/me/repo/blob/v1.1.0-beta.1/README.md#quick-start) in the README.

## What's changed

### ⚠️ Breaking changes

- Keep the log. Move it to log.txt. @B@

### ✨ Features

- **setup:** Add a thing @A@

<details>
<summary>🧰 Other changes (1)</summary>

- ci: run the tests @D@

</details>

**Full changelog:** [v1.0.0...v1.1.0-beta.1](https://github.com/me/repo/compare/v1.0.0...v1.1.0-beta.1)

<details>
<summary>🔒 SHA-256</summary>

```
0123abcd  setup-yt-dlp.tar.xz
4567ef01  setup-yt-dlp-standalone.tar.xz
```

To check your downloads, put them and their `.sha256` files in a folder of their own, and run the command for your system there. Delete older copies first, so your browser doesn't rename the new ones.

- macOS: `shasum -a 256 -c *.sha256`

</details>
EOF
    )
    for c in A:"$a" B:"$b" D:"$d"; do
        sha=${c#*:}
        expected=${expected//@${c%%:*}@/"([\`${sha:0:7}\`](https://github.com/me/repo/commit/$sha))"}
    done
    assert_output "$expected"
}

@test "the notes group the commits since the last release by type" {
    new_repo
    commit "feat: add the first thing" src/a
    git tag v0.1.0
    commit "feat: add a second thing" src/a
    commit "fix(setup): mend the first thing" src/a
    commit "perf: start faster" src/a
    commit "docs: explain a thing" README.md
    commit "docs(contributing): explain the tests" CONTRIBUTING.md
    commit "refactor: rename a thing" src/c
    git revert --no-edit HEAD >/dev/null
    commit "feat: add a broken thing" src/d
    commit "revert: feat: add a broken thing" src/d
    commit "test: test the second thing" test/a.bats
    git tag v0.2.0-beta.1

    run -0 notes v0.2.0-beta.1
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
    refute_output --partial 'broken thing'
    refute_output --partial 'No user-facing changes'
}

@test "the notes list a breaking change once, with its footer" {
    new_repo
    commit "feat(setup)!: drop --output

Why.

BREAKING CHANGE: Pass the folder
after --downloader instead.
Co-Authored-By: Someone <a@b.c>" src/a
    commit "fix!: keep the log" src/a
    commit "fix: don't print an error" src/a
    git tag v1.0.0

    run -0 notes v1.0.0
    assert_output --regexp "### ⚠️ Breaking changes

- \*\*setup:\*\* Drop --output\. Pass the folder after --downloader instead\. $link
- Keep the log $link
"
    assert_line --regexp "^- Don't print an error $link\$"
    refute_output --partial '### ✨ Features'
}

@test "the notes say when nothing users see has changed" {
    new_repo
    commit "ci: run the tests" .github/workflows/ci.yml
    git tag v1.0.0
    commit "Tidy the scripts" src/a
    git tag v1.0.1

    run -0 notes v1.0.0
    assert_line 'No user-facing changes.'
    # A commit without a type may still change the scripts.
    run -0 notes v1.0.1
    refute_output --partial 'No user-facing changes'
    assert_line --regexp "^- Tidy the scripts $link\$"
}

@test "the notes start with the tag's summary" {
    new_repo
    commit "feat: add a thing

A body that isn't the tag's." src/a
    git tag v1.0.0
    git tag -a -m v1.1.0 v1.1.0
    git tag -a -m "setup-yt-dlp 1.2.0" -m "Adds a thing." v1.2.0
    git tag -a -m v1.3.0 -m "Adds another." -m "-----BEGIN SSH SIGNATURE-----
U1NIU0lH
-----END SSH SIGNATURE-----" v1.3.0

    run -0 notes v1.0.0
    assert_line --index 0 '## Download'
    run -0 notes v1.1.0
    assert_line --index 0 '## Download'
    run -0 notes v1.2.0
    assert_line --index 0 'Adds a thing.'
    assert_line --index 1 '## Download'
    run -0 notes v1.3.0
    assert_line --index 0 'Adds another.'
    refute_output --partial 'SIGNATURE'
}

@test "the notes link the install steps in the README at the tag" {
    new_repo
    # shellcheck disable=SC2016 # the backticks are Markdown
    printf '# App\n\n```\n## Install from a code block\n```\n\n## Usage\n\n## Download a release (easiest)\n' >README.md
    git add README.md
    git commit -q -m "docs: write the README"
    git tag v1.0.0
    printf '# App\n\n## Usage\n' >README.md
    git commit -q -am "docs: drop the install steps"
    git tag v1.1.0

    run -0 notes v1.0.0
    assert_line 'For how to install it, see [Download a release (easiest)](https://github.com/me/repo/blob/v1.0.0/README.md#download-a-release-easiest) in the README.'
    run -0 notes v1.1.0
    assert_line 'For how to install it, see the [README](https://github.com/me/repo/blob/v1.1.0/README.md).'
}

@test "the notes refuse a file they don't know" {
    new_repo
    commit "feat: add a thing" src/a
    git tag v1.0.0
    printf '%s  other.zip\n' 0123abcd >"$BATS_TEST_TMPDIR/sums"

    run -1 --separate-stderr notes v1.0.0 "$BATS_TEST_TMPDIR/sums"
    assert_stderr 'error: other.zip matches none of the files in file_globs'
}

@test "the notes for a final release have no pre-release warning" {
    new_repo
    commit "feat: add the first thing" src/a
    git tag v1.0.0
    run -0 notes v1.0.0
    refute_output --partial 'pre-release'
    refute_output --partial 'SHA-256'
    assert_line '**Full changelog:** [all commits](https://github.com/me/repo/commits/v1.0.0)'
}

@test "the notes for a final release list everything since the last final release" {
    new_repo
    commit "feat: add the first thing" src/a
    git tag v1.0.0-beta.1
    commit "feat: add a second thing" src/a
    git tag v1.0.0
    commit "feat: add a third thing" src/a
    git tag v1.1.0-rc.1
    commit "feat: add a fourth thing" src/a
    git tag v1.1.0

    run -0 notes v1.0.0
    assert_output --regexp "- Add the first thing $link
- Add a second thing $link"
    assert_line '**Full changelog:** [all commits](https://github.com/me/repo/commits/v1.0.0)'

    run -0 notes v1.1.0
    refute_output --partial 'Add a second thing'
    assert_output --regexp "- Add a third thing $link
- Add a fourth thing $link"
    assert_line '**Full changelog:** [v1.0.0...v1.1.0](https://github.com/me/repo/compare/v1.0.0...v1.1.0)'

    # A pre-release still lists only what's new since the tag before it.
    run -0 notes v1.1.0-rc.1
    refute_output --partial 'Add a second thing'
    assert_line '**Full changelog:** [v1.0.0...v1.1.0-rc.1](https://github.com/me/repo/compare/v1.0.0...v1.1.0-rc.1)'
}
