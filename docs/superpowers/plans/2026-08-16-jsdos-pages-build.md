# MARS.COM Build Scripts and js-dos Pages Player — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Assemble `MARS.ASM` into a runnable `MARS.COM` with a reproducible script, and publish a GitHub Pages site that runs that binary in the browser via a self-hosted js-dos.

**Architecture:** Plain POSIX-ish bash scripts under `scripts/`, each with one responsibility, sharing `scripts/lib.sh`. Version pins live in a single `versions.env`. A bash test harness under `tests/` exercises each script. Two GitHub Actions workflows: one verifies the build on every push, one builds and deploys the site to Pages. Nothing is fetched from a third-party origin at page-view time.

**Tech Stack:** JWasm v2.20 (MASM-compatible assembler, built from source), js-dos 8.4.1 (fetched from npm at build time), GitHub Actions, GitHub Pages. No package manager, no framework, no runtime dependencies.

**Spec:** `docs/superpowers/specs/2026-08-16-mars-com-jsdos-pages-design.md`

## Global Constraints

- **Assembler:** JWasm, pinned to tag `v2.20`, repo `https://github.com/Baron-von-Riedesel/JWasm.git`. Build with `make -f GccUnix.mak`; binary lands at `build/GccUnixR/jwasm` inside the JWasm checkout.
- **macOS caveat (found during execution, not anticipated by this plan):** `GccUnix.mak` targets Linux/FreeBSD. On Darwin it needs (a) an include shim so `<malloc.h>` resolves to `<stdlib.h>`, injected by overriding `inc_dirs`, and (b) removal of the GNU-only `-s` and `-Wl,-Map` link flags, which are hardcoded in the recipe and must be `sed`-stripped. `scripts/build.sh` applies both automatically when `uname -s` is `Darwin`. Verified: the macOS/clang/ARM64 build produces a `MARS.COM` byte-identical to the Linux/gcc/aarch64 build.
- **js-dos:** pinned to version `8.4.1`, fetched via `npm pack js-dos@8.4.1`.
- **Emulator backend:** `dosbox` (`wdosbox.js` + `wdosbox.wasm`, ~1.5 MB). Do **not** ship `wdosbox-x*` (~15.5 MB combined).
- **Expected build output:** `MARS.COM`, exactly **1550 bytes**, SHA-256 `10a1bb6c319296dd8628e8fd2d705b50fca97b82d6d9a811c91c30c06199d773`. Verified byte-identical under JWasm v2.20 and v2.21.
- **`.COM` size ceiling:** 65280 bytes (0xFF00). CI fails above this.
- **DOSBox machine:** `machine=vgaonly` is mandatory — the renderer uses VGA mode 13h and reprograms the palette DAC; the default `svga_s3` produces artifacts.
- **Bundle layout:** a ZIP named `mars.jsdos` containing `MARS.COM` at the root and `.jsdos/dosbox.conf`. js-dos does **not** auto-mount — the `[autoexec]` section must contain `mount c .` then `c:` then the command. (Confirmed against js-dos's own bundle generator in `emulators.js`.)
- **js-dos asset path:** `pathPrefix` must point at the *emulators* directory and end with a slash (the built-in default is `https://v8.js-dos.com/latest/emulators/`).
- **No third-party runtime requests.** All assets served from the Pages origin.
- **Never commit** `build/`, `_site/`, `.toolchain/`, or `MARS.COM`.
- **Attribution:** original by Tim J. Clarke (1993); disassembly and reduction by Wojciech Bruzda (2021). GPL-3.0 preserved.
- **Shell style:** every script starts `#!/usr/bin/env bash` and sources `scripts/lib.sh`, which sets `set -euo pipefail`.

---

### Task 1: Scaffolding — version pins, shared library, test harness

**Files:**
- Create: `versions.env`
- Create: `scripts/lib.sh`
- Create: `tests/lib.sh`
- Create: `tests/run-tests.sh`
- Create: `tests/test-lib.sh`
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/lib.sh` exporting `REPO_ROOT`, `BUILD_DIR`, `SITE_OUT`, `TOOLCHAIN_DIR` (all absolute paths) and functions `log(msg)`, `die(msg)` (exit 1), `need(tool)` (die if absent); plus every variable from `versions.env`. `tests/lib.sh` exports `assert_eq(actual, expected, label)`, `assert_file_exists(path)`, `assert_contains(haystack_file, needle)`, `assert_success(cmd...)`, and `finish_tests()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test-lib.sh`:

```bash
#!/usr/bin/env bash
# Verifies scripts/lib.sh exposes the contract the other scripts rely on.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

assert_file_exists "$REPO_ROOT/MARS.ASM"   # REPO_ROOT points at the repo
assert_eq "$BUILD_DIR" "$REPO_ROOT/build" "BUILD_DIR derived from REPO_ROOT"
assert_eq "$SITE_OUT" "$REPO_ROOT/_site" "SITE_OUT derived from REPO_ROOT"
assert_eq "$JWASM_TAG" "v2.20" "JWasm pin loaded from versions.env"
assert_eq "$JSDOS_VERSION" "8.4.1" "js-dos pin loaded from versions.env"
assert_eq "$MARS_COM_SIZE" "1550" "expected binary size loaded"

# die must exit non-zero and print to stderr
if ( die "boom" ) 2>/dev/null; then
  fail "die should exit non-zero"
else
  pass "die exits non-zero"
fi

finish_tests
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tests/test-lib.sh`
Expected: FAIL — `tests/lib.sh: No such file or directory`.

- [ ] **Step 3: Write the test harness library**

Create `tests/lib.sh`:

```bash
#!/usr/bin/env bash
# Minimal assertion helpers. No external test framework dependency.
TESTS_RUN=0
TESTS_FAILED=0

pass() { TESTS_RUN=$((TESTS_RUN + 1)); printf '  \033[0;32mok\033[0m %s\n' "$1"; }

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  \033[0;31mFAIL\033[0m %s\n' "$1"
}

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

assert_file_exists() {
  if [ -f "$1" ]; then pass "file exists: $1"; else fail "file missing: $1"; fi
}

assert_contains() {
  local file="$1" needle="$2"
  if grep -qF -- "$needle" "$file" 2>/dev/null; then
    pass "$file contains '$needle'"
  else
    fail "$file does not contain '$needle'"
  fi
}

assert_success() {
  if "$@" >/dev/null 2>&1; then pass "command succeeded: $*"; else fail "command failed: $*"; fi
}

finish_tests() {
  printf '\n  %d assertion(s), %d failure(s)\n' "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ] || exit 1
}
```

- [ ] **Step 4: Write the version pins**

Create `versions.env`:

```sh
# Single source of truth for pinned versions.
# Sourced by scripts/lib.sh; plain KEY=value so CI can read it too.

# JWasm — MASM-compatible assembler used to build MARS.COM
JWASM_TAG=v2.20
JWASM_REPO=https://github.com/Baron-von-Riedesel/JWasm.git

# js-dos — browser DOS emulator, fetched at site build time
JSDOS_VERSION=8.4.1

# Expected build output (JWasm v2.20 and v2.21 agree byte-for-byte)
MARS_COM_SIZE=1550
MARS_COM_SHA256=10a1bb6c319296dd8628e8fd2d705b50fca97b82d6d9a811c91c30c06199d773

# Hard ceiling for a DOS .COM image (0xFF00)
MARS_COM_MAX_SIZE=65280
```

- [ ] **Step 5: Write the shared script library**

Create `scripts/lib.sh`:

```bash
#!/usr/bin/env bash
# Shared helpers for every script in this repo. Source it, don't execute it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
SITE_OUT="$REPO_ROOT/_site"
TOOLCHAIN_DIR="$REPO_ROOT/.toolchain"

# shellcheck source=/dev/null
. "$REPO_ROOT/versions.env"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"; }
```

- [ ] **Step 6: Write the test runner**

Create `tests/run-tests.sh`:

```bash
#!/usr/bin/env bash
# Runs every tests/test-*.sh and reports a combined result.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

failed=0
for t in test-*.sh; do
  printf '\n\033[1m%s\033[0m\n' "$t"
  bash "$t" || failed=$((failed + 1))
done

printf '\n'
if [ "$failed" -ne 0 ]; then
  printf '\033[1;31m%d test file(s) failed\033[0m\n' "$failed"
  exit 1
fi
printf '\033[1;32mAll test files passed\033[0m\n'
```

- [ ] **Step 7: Write .gitignore**

Create `.gitignore`:

```gitignore
# Build outputs — MARS.ASM is the single source of truth
build/
_site/
.toolchain/
MARS.COM
*.jsdos

# Fetched dependencies
node_modules/
*.tgz

# OS turds
.DS_Store
```

- [ ] **Step 8: Run the tests and make sure they pass**

Run: `chmod +x tests/run-tests.sh tests/test-lib.sh && bash tests/run-tests.sh`
Expected: PASS — 7 assertions, 0 failures.

(Count check: 1 `assert_file_exists`, 5 `assert_eq`, 1 `die` branch = 7.)

- [ ] **Step 9: Commit**

```bash
git add versions.env scripts/lib.sh tests/ .gitignore
git commit -m "build: add version pins, shared script library, and test harness"
```

---

### Task 2: Build script — assemble MARS.ASM into MARS.COM

**Files:**
- Create: `scripts/build.sh`
- Create: `tests/test-build.sh`

**Interfaces:**
- Consumes: `scripts/lib.sh` (`REPO_ROOT`, `BUILD_DIR`, `TOOLCHAIN_DIR`, `JWASM_TAG`, `JWASM_REPO`, `MARS_COM_MAX_SIZE`, `log`, `die`, `need`).
- Produces: `build/MARS.COM`. Accepts flags `--docker` (run the whole build in a `debian:bookworm-slim` container) and `--check` (after assembling, verify size against `MARS_COM_SIZE` and exit non-zero on mismatch). Exposes no functions to later tasks; later tasks depend only on the output path `build/MARS.COM`.

- [ ] **Step 1: Write the failing test**

Create `tests/test-build.sh`:

```bash
#!/usr/bin/env bash
# Verifies the assembler pipeline produces the expected MARS.COM.
# First run is slow: it builds JWasm from source.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

rm -f "$BUILD_DIR/MARS.COM"
assert_success bash "$REPO_ROOT/scripts/build.sh"
assert_file_exists "$BUILD_DIR/MARS.COM"

actual_size=$(wc -c < "$BUILD_DIR/MARS.COM" | tr -d ' ')
assert_eq "$actual_size" "$MARS_COM_SIZE" "MARS.COM is the expected size"

actual_sha=$(shasum -a 256 "$BUILD_DIR/MARS.COM" 2>/dev/null | cut -d' ' -f1 \
  || sha256sum "$BUILD_DIR/MARS.COM" | cut -d' ' -f1)
assert_eq "$actual_sha" "$MARS_COM_SHA256" "MARS.COM is byte-identical to the pinned build"

# --check must succeed on a good build
assert_success bash "$REPO_ROOT/scripts/build.sh" --check

finish_tests
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tests/test-build.sh`
Expected: FAIL — `scripts/build.sh` does not exist, so `assert_success` reports a failed command and the file assertions fail.

- [ ] **Step 3: Write the build script**

Create `scripts/build.sh`:

```bash
#!/usr/bin/env bash
# Assembles MARS.ASM into a runnable DOS .COM image.
#
# MARS.ASM is MASM/TASM dialect (.model tiny, org 100h, COMMENT # blocks),
# so it needs a MASM-compatible assembler — NASM cannot build it. We use
# JWasm, pinned in versions.env. Because the model is tiny, the assembler
# emits the .COM memory image directly; there is no link step.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  cat <<'EOF'
Usage: scripts/build.sh [--docker] [--check]

  --docker  Run the build inside a container (no host compiler needed).
  --check   Verify the output matches the pinned size and SHA-256.

Assembler resolution order:
  1. $JWASM environment variable
  2. jwasm on PATH
  3. build JWasm from source into .toolchain/ (needs gcc, make, git)
EOF
}

use_docker=0
do_check=0
for arg in "$@"; do
  case "$arg" in
    --docker) use_docker=1 ;;
    --check)  do_check=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $arg (try --help)" ;;
  esac
done

if [ "$use_docker" -eq 1 ]; then
  need docker
  log "Building inside debian:bookworm-slim"
  docker run --rm -v "$REPO_ROOT:/repo" -w /repo debian:bookworm-slim bash -c '
    set -e
    apt-get update -qq >/dev/null
    apt-get install -y -qq build-essential git ca-certificates >/dev/null 2>&1
    bash scripts/build.sh
  '
  exit $?
fi

# --- resolve an assembler -----------------------------------------------
resolve_jwasm() {
  if [ -n "${JWASM:-}" ]; then
    [ -x "$JWASM" ] || die "\$JWASM is set to '$JWASM' but that is not executable"
    printf '%s' "$JWASM"
    return
  fi

  if command -v jwasm >/dev/null 2>&1; then
    command -v jwasm
    return
  fi

  local cached="$TOOLCHAIN_DIR/bin/jwasm"
  if [ -x "$cached" ]; then
    printf '%s' "$cached"
    return
  fi

  log "No assembler found; building JWasm $JWASM_TAG from source" >&2
  need git
  need make
  command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 \
    || die "no C compiler found. Install gcc/clang, set \$JWASM to a jwasm binary, or rerun with --docker"

  local src="$TOOLCHAIN_DIR/JWasm"
  rm -rf "$src"
  mkdir -p "$TOOLCHAIN_DIR/bin"
  git clone -q "$JWASM_REPO" "$src" >&2
  ( cd "$src" && git checkout -q "$JWASM_TAG" && make -f GccUnix.mak >/dev/null 2>&1 ) \
    || die "JWasm build failed. Rerun with --docker, or set \$JWASM to a prebuilt binary."

  local built
  built="$(find "$src" -name jwasm -type f -perm -u+x | head -1)"
  [ -n "$built" ] || die "JWasm built but no 'jwasm' binary was produced"
  cp "$built" "$cached"
  printf '%s' "$cached"
}

JWASM_BIN="$(resolve_jwasm)"
log "Assembler: $JWASM_BIN"

# --- assemble ------------------------------------------------------------
mkdir -p "$BUILD_DIR"
out="$BUILD_DIR/MARS.COM"
rm -f "$out"

# -bin: raw binary output, which for .model tiny is exactly a .COM image.
"$JWASM_BIN" -bin -Fo="$out" "$REPO_ROOT/MARS.ASM" \
  || die "assembly failed"

[ -s "$out" ] || die "assembler produced an empty $out"

size=$(wc -c < "$out" | tr -d ' ')
[ "$size" -le "$MARS_COM_MAX_SIZE" ] \
  || die "$out is $size bytes, which exceeds the $MARS_COM_MAX_SIZE byte .COM ceiling"

if command -v shasum >/dev/null 2>&1; then
  sha=$(shasum -a 256 "$out" | cut -d' ' -f1)
else
  sha=$(sha256sum "$out" | cut -d' ' -f1)
fi

log "Built $out — $size bytes, sha256 $sha"

if [ "$do_check" -eq 1 ]; then
  [ "$size" = "$MARS_COM_SIZE" ] \
    || die "size mismatch: expected $MARS_COM_SIZE bytes, got $size. If MARS.ASM changed on purpose, update versions.env."
  [ "$sha" = "$MARS_COM_SHA256" ] \
    || die "sha256 mismatch: expected $MARS_COM_SHA256, got $sha. If MARS.ASM changed on purpose, update versions.env."
  log "Reproducibility check passed"
fi
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `chmod +x scripts/build.sh && bash tests/test-build.sh`
Expected: PASS — 5 assertions, 0 failures. First run takes 1–2 minutes (JWasm compile); subsequent runs are instant because `.toolchain/bin/jwasm` is cached.

- [ ] **Step 5: Commit**

```bash
git add scripts/build.sh tests/test-build.sh
git commit -m "build: assemble MARS.ASM into MARS.COM with pinned JWasm"
```

---

### Task 3: DOSBox config and js-dos bundle

**Files:**
- Create: `site/dosbox.conf`
- Create: `scripts/bundle.sh`
- Create: `tests/test-bundle.sh`

**Interfaces:**
- Consumes: `scripts/lib.sh`; `build/MARS.COM` from Task 2.
- Produces: `build/mars.jsdos` — a ZIP with `MARS.COM` at the root and `.jsdos/dosbox.conf` inside. Task 5 copies this file into the site output as `mars.jsdos`.

- [ ] **Step 1: Write the failing test**

Create `tests/test-bundle.sh`:

```bash
#!/usr/bin/env bash
# Verifies the .jsdos bundle has the layout js-dos expects.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

bash "$REPO_ROOT/scripts/build.sh" >/dev/null 2>&1
assert_success bash "$REPO_ROOT/scripts/bundle.sh"
assert_file_exists "$BUILD_DIR/mars.jsdos"

listing="$BUILD_DIR/.bundle-listing.txt"
unzip -l "$BUILD_DIR/mars.jsdos" > "$listing"
assert_contains "$listing" "MARS.COM"
assert_contains "$listing" ".jsdos/dosbox.conf"

conf="$BUILD_DIR/.bundle-conf.txt"
unzip -p "$BUILD_DIR/mars.jsdos" ".jsdos/dosbox.conf" > "$conf"
assert_contains "$conf" "machine=vgaonly"
assert_contains "$conf" "mount c ."
assert_contains "$conf" "MARS.COM"

rm -f "$listing" "$conf"
finish_tests
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tests/test-bundle.sh`
Expected: FAIL — `scripts/bundle.sh` does not exist; `build/mars.jsdos` missing.

- [ ] **Step 3: Write the DOSBox config**

Create `site/dosbox.conf`:

```ini
# DOSBox configuration for the MARS landscape renderer.
#
# machine=vgaonly is mandatory, not cosmetic. MARS writes directly to VGA
# mode 13h and reprograms the palette DAC. DOSBox's default svga_s3
# emulation changes DAC behaviour and produces visible artifacts — the
# original author's notes call for "-machine vgaonly" explicitly.

[sdl]
autolock=true

[dosbox]
machine=vgaonly

[cpu]
core=auto
cputype=auto
cycles=auto

[render]
aspect=true

[autoexec]
echo off
mount c .
c:
MARS.COM
```

- [ ] **Step 4: Write the bundle script**

Create `scripts/bundle.sh`:

```bash
#!/usr/bin/env bash
# Packages MARS.COM and its DOSBox config into a js-dos .jsdos bundle.
#
# A .jsdos bundle is a ZIP whose root becomes drive C: and which carries
# its DOSBox config at .jsdos/dosbox.conf. js-dos does NOT auto-mount, so
# the [autoexec] section in site/dosbox.conf does the mount itself.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need zip

com="$BUILD_DIR/MARS.COM"
[ -f "$com" ] || die "$com not found — run scripts/build.sh first"

staging="$BUILD_DIR/bundle"
out="$BUILD_DIR/mars.jsdos"

rm -rf "$staging" "$out"
mkdir -p "$staging/.jsdos"

cp "$com" "$staging/MARS.COM"
cp "$REPO_ROOT/site/dosbox.conf" "$staging/.jsdos/dosbox.conf"

# -X strips extra file attributes so the bundle is reproducible.
( cd "$staging" && zip -q -r -X "$out" . )

log "Bundled $out ($(wc -c < "$out" | tr -d ' ') bytes)"
```

- [ ] **Step 5: Run the tests and make sure they pass**

Run: `chmod +x scripts/bundle.sh && bash tests/test-bundle.sh`
Expected: PASS — 7 assertions, 0 failures.

(Count check: 1 `assert_success`, 1 `assert_file_exists`, 5 `assert_contains` = 7.)

- [ ] **Step 6: Commit**

```bash
git add site/dosbox.conf scripts/bundle.sh tests/test-bundle.sh
git commit -m "build: package MARS.COM into a js-dos bundle with vgaonly config"
```

---

### Task 4: Fetch pinned js-dos assets

**Files:**
- Create: `scripts/fetch-jsdos.sh`
- Create: `tests/test-fetch-jsdos.sh`

**Interfaces:**
- Consumes: `scripts/lib.sh` (`BUILD_DIR`, `JSDOS_VERSION`).
- Produces: `build/js-dos/` containing `js-dos.js`, `js-dos.css`, and `emulators/{emulators.js,wdosbox.js,wdosbox.wasm}`. Task 5 copies this directory into the site output as `js-dos/`.

- [ ] **Step 1: Write the failing test**

Create `tests/test-fetch-jsdos.sh`:

```bash
#!/usr/bin/env bash
# Verifies we fetch exactly the js-dos assets the page needs, and no more.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

assert_success bash "$REPO_ROOT/scripts/fetch-jsdos.sh"

assert_file_exists "$BUILD_DIR/js-dos/js-dos.js"
assert_file_exists "$BUILD_DIR/js-dos/js-dos.css"
assert_file_exists "$BUILD_DIR/js-dos/emulators/emulators.js"
assert_file_exists "$BUILD_DIR/js-dos/emulators/wdosbox.js"
assert_file_exists "$BUILD_DIR/js-dos/emulators/wdosbox.wasm"

# The heavy dosbox-x builds must NOT be shipped (~15.5 MB of dead weight).
if [ -f "$BUILD_DIR/js-dos/emulators/wdosbox-x.wasm" ]; then
  fail "wdosbox-x.wasm was shipped but is not needed"
else
  pass "dosbox-x builds excluded"
fi

finish_tests
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tests/test-fetch-jsdos.sh`
Expected: FAIL — `scripts/fetch-jsdos.sh` does not exist.

- [ ] **Step 3: Write the fetch script**

Create `scripts/fetch-jsdos.sh`:

```bash
#!/usr/bin/env bash
# Downloads a pinned js-dos release and extracts only the assets the page
# needs. This runs at BUILD time, never at page-view time — the deployed
# site serves js-dos from its own origin, so it does not depend on a CDN.
#
# We ship the plain dosbox backend (wdosbox, ~1.5 MB) and deliberately skip
# dosbox-x (~15.5 MB across two builds). MARS only needs machine=vgaonly,
# which plain DOSBox supports.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need npm
need tar

dest="$BUILD_DIR/js-dos"
work="$BUILD_DIR/.jsdos-download"

if [ -f "$dest/js-dos.js" ] && [ "${FORCE_FETCH:-0}" != "1" ]; then
  log "js-dos $JSDOS_VERSION already present in $dest (set FORCE_FETCH=1 to refetch)"
  exit 0
fi

rm -rf "$work" "$dest"
mkdir -p "$work" "$dest/emulators"

log "Fetching js-dos $JSDOS_VERSION from npm"
( cd "$work" && npm pack "js-dos@$JSDOS_VERSION" >/dev/null ) \
  || die "npm pack failed for js-dos@$JSDOS_VERSION"

tarball="$work/js-dos-$JSDOS_VERSION.tgz"
[ -f "$tarball" ] || die "expected tarball $tarball was not produced"

tar xzf "$tarball" -C "$work" \
  package/dist/js-dos.js \
  package/dist/js-dos.css \
  package/dist/emulators/emulators.js \
  package/dist/emulators/wdosbox.js \
  package/dist/emulators/wdosbox.wasm \
  || die "js-dos tarball did not contain the expected dist layout"

cp "$work/package/dist/js-dos.js"  "$dest/js-dos.js"
cp "$work/package/dist/js-dos.css" "$dest/js-dos.css"
cp "$work/package/dist/emulators/emulators.js" "$dest/emulators/emulators.js"
cp "$work/package/dist/emulators/wdosbox.js"   "$dest/emulators/wdosbox.js"
cp "$work/package/dist/emulators/wdosbox.wasm" "$dest/emulators/wdosbox.wasm"

rm -rf "$work"

log "js-dos $JSDOS_VERSION staged in $dest ($(du -sh "$dest" | cut -f1))"
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `chmod +x scripts/fetch-jsdos.sh && bash tests/test-fetch-jsdos.sh`
Expected: PASS — 7 assertions, 0 failures.

(Count check: 1 `assert_success`, 5 `assert_file_exists`, 1 dosbox-x branch = 7.)

- [ ] **Step 5: Commit**

```bash
git add scripts/fetch-jsdos.sh tests/test-fetch-jsdos.sh
git commit -m "build: fetch pinned js-dos 8.4.1 assets at build time"
```

---

### Task 5: The page and the site build

**Files:**
- Create: `site/index.html`
- Create: `site/style.css`
- Create: `scripts/build-site.sh`
- Create: `tests/test-site.sh`

**Interfaces:**
- Consumes: `scripts/lib.sh`; `build/MARS.COM` (Task 2), `build/mars.jsdos` (Task 3), `build/js-dos/` (Task 4).
- Produces: `_site/` containing `index.html`, `style.css`, `mars.jsdos`, `MARS.COM`, `mars_4_3.png`, `MARS.ASM`, and `js-dos/`. Task 6 serves it; Task 8 deploys it.

- [ ] **Step 1: Write the failing test**

Create `tests/test-site.sh`:

```bash
#!/usr/bin/env bash
# Verifies the composed site is complete and self-contained.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

assert_success bash "$REPO_ROOT/scripts/build-site.sh"

assert_file_exists "$SITE_OUT/index.html"
assert_file_exists "$SITE_OUT/style.css"
assert_file_exists "$SITE_OUT/mars.jsdos"
assert_file_exists "$SITE_OUT/MARS.COM"
assert_file_exists "$SITE_OUT/MARS.ASM"
assert_file_exists "$SITE_OUT/js-dos/js-dos.js"
assert_file_exists "$SITE_OUT/js-dos/emulators/wdosbox.wasm"

# The page must reference its own copies, not a CDN.
assert_contains "$SITE_OUT/index.html" 'js-dos/emulators/'
assert_contains "$SITE_OUT/index.html" 'mars.jsdos'

# No third-party origins anywhere in the page.
if grep -qE 'https?://(v8\.)?js-dos\.com|cdn\.|unpkg|jsdelivr' "$SITE_OUT/index.html"; then
  fail "index.html references a third-party asset origin"
else
  pass "no third-party asset origins in index.html"
fi

# Attribution must survive any future edit of the page.
assert_contains "$SITE_OUT/index.html" "Tim J. Clarke"
assert_contains "$SITE_OUT/index.html" "Bruzda"

finish_tests
```

Note: the third-party check greps for asset origins, so `index.html` must not
contain a scheme-qualified `js-dos.com` URL. The page as written credits js-dos
in plain text and points every anchor at github.com, so it passes. If you later
want a clickable js-dos link on the page, relax this assertion deliberately
rather than working around it.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tests/test-site.sh`
Expected: FAIL — `scripts/build-site.sh` does not exist.

- [ ] **Step 3: Write the page**

Create `site/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MARS — a martian landscape in 1550 bytes</title>
<meta name="description" content="Tim J. Clarke's 1993 martian landscape renderer, disassembled and reduced to about 1.5 KB, running in your browser.">
<link rel="stylesheet" href="js-dos/js-dos.css">
<link rel="stylesheet" href="style.css">
</head>
<body>

<main>
  <header>
    <h1>MARS</h1>
    <p class="tagline">A martian landscape renderer from 1993, in <strong>1550 bytes</strong>.</p>
  </header>

  <div id="player">
    <div id="dos"></div>
    <noscript><p class="notice">This demo needs JavaScript to run the DOS emulator.</p></noscript>
    <p id="error" class="notice" hidden></p>
  </div>

  <p class="hint">
    Click the canvas to capture your mouse &mdash; moving it pans the camera.
    Press <kbd>Esc</kbd> to release.
  </p>

  <section>
    <h2>What this is</h2>
    <p>
      In 1993 <strong>Tim J. Clarke</strong> wrote a real-time martian landscape
      renderer that fit in a 5649-byte DOS executable. In 2021
      <strong>Wojciech Bruzda</strong> disassembled it, rewrote it, and reduced it
      to roughly a tenth of that size &mdash; the binary running above is
      assembled from that annotated source.
    </p>
    <p>
      It draws into VGA mode 13h and reprograms the palette DAC directly, which
      is why the emulator here is pinned to <code>machine=vgaonly</code>.
    </p>
  </section>

  <footer>
    <ul class="links">
      <li><a href="MARS.ASM">Read the annotated assembly</a></li>
      <li><a href="MARS.COM" download>Download MARS.COM (1550 bytes)</a></li>
      <li><a href="https://github.com/dtz-labs/MARS.COM">This repository</a></li>
      <li><a href="https://github.com/matrix-toolbox/MARS.COM">Upstream by Wojciech Bruzda</a></li>
    </ul>
    <p class="legal">
      Original renderer by Tim J. Clarke, 1993. Disassembly and size reduction by
      Wojciech Bruzda, 2021. Source released under GPL-3.0. Emulation by js-dos.
    </p>
  </footer>
</main>

<script src="js-dos/js-dos.js"></script>
<script>
  (function () {
    var errorEl = document.getElementById("error");

    function showError(message) {
      errorEl.textContent = message;
      errorEl.hidden = false;
    }

    if (typeof Dos !== "function") {
      showError("Could not load the DOS emulator. Try reloading the page.");
      return;
    }

    try {
      Dos(document.getElementById("dos"), {
        url: "mars.jsdos",
        // Point every emulator asset at our own origin. Without this,
        // js-dos falls back to its public CDN.
        pathPrefix: "js-dos/emulators/",
        backend: "dosbox",
        theme: "dark",
        kiosk: true,
        noCloud: true,
        autoStart: true,
        countDownStart: 0,
        imageRendering: "pixelated",
        mouseCapture: true,
        onEvent: function (event) {
          if (event === "emu-ready" || event === "ci-ready") {
            errorEl.hidden = true;
          }
        }
      });
    } catch (e) {
      showError("The DOS emulator failed to start: " + e.message);
    }
  })();
</script>

</body>
</html>
```

- [ ] **Step 4: Write the stylesheet**

Create `site/style.css`:

```css
/* Dark, low-chrome framing so the 320x200 canvas is the loudest thing here. */
:root {
  --bg: #0d0b0a;
  --fg: #e8ddd4;
  --muted: #9a8d83;
  --accent: #d97742;
  --rule: #2a2320;
}

* { box-sizing: border-box; }

body {
  margin: 0;
  padding: 2rem 1.25rem 4rem;
  background: var(--bg);
  color: var(--fg);
  font: 16px/1.65 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
}

main { max-width: 46rem; margin: 0 auto; }

header { text-align: center; margin-bottom: 1.75rem; }

h1 {
  margin: 0;
  font-size: clamp(2.5rem, 9vw, 4rem);
  letter-spacing: 0.22em;
  text-indent: 0.22em;
  color: var(--accent);
  font-weight: 700;
}

.tagline { margin: 0.35rem 0 0; color: var(--muted); }

/* The emulator canvas. 4:3 keeps mode 13h's aspect honest. */
#player {
  position: relative;
  aspect-ratio: 4 / 3;
  width: 100%;
  background: #000;
  border: 1px solid var(--rule);
  border-radius: 4px;
  overflow: hidden;
}

#dos { width: 100%; height: 100%; }

.notice {
  position: absolute;
  inset: auto 0 0;
  margin: 0;
  padding: 0.75rem 1rem;
  background: #3a1410;
  color: #ffb4a2;
  font-size: 0.9rem;
  text-align: center;
}

.hint {
  margin: 0.9rem 0 2.5rem;
  color: var(--muted);
  font-size: 0.9rem;
  text-align: center;
}

kbd {
  padding: 0.1em 0.4em;
  border: 1px solid var(--rule);
  border-radius: 3px;
  background: #191412;
  font: 0.85em ui-monospace, SFMono-Regular, Menlo, monospace;
}

section { border-top: 1px solid var(--rule); padding-top: 1.5rem; }

h2 { font-size: 1.05rem; letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); }

code {
  padding: 0.1em 0.35em;
  border-radius: 3px;
  background: #191412;
  color: var(--accent);
  font: 0.9em ui-monospace, SFMono-Regular, Menlo, monospace;
}

footer { margin-top: 2.5rem; border-top: 1px solid var(--rule); padding-top: 1.5rem; }

.links { list-style: none; margin: 0 0 1.25rem; padding: 0; display: grid; gap: 0.5rem; }

a { color: var(--accent); text-underline-offset: 3px; }
a:hover { color: #f0a070; }

.legal { margin: 0; color: var(--muted); font-size: 0.82rem; }

@media (max-width: 480px) {
  body { padding: 1.25rem 0.75rem 3rem; }
}
```

- [ ] **Step 5: Write the site build script**

Create `scripts/build-site.sh`:

```bash
#!/usr/bin/env bash
# Composes the deployable site from the built binary, the js-dos bundle,
# the fetched emulator assets, and the static page sources.
#
# Everything the browser loads is copied into _site/, so the deployed page
# makes no third-party requests at view time.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Building MARS.COM"
bash "$REPO_ROOT/scripts/build.sh"

log "Bundling for js-dos"
bash "$REPO_ROOT/scripts/bundle.sh"

log "Fetching js-dos $JSDOS_VERSION"
bash "$REPO_ROOT/scripts/fetch-jsdos.sh"

log "Composing $SITE_OUT"
rm -rf "$SITE_OUT"
mkdir -p "$SITE_OUT"

cp "$REPO_ROOT/site/index.html" "$SITE_OUT/index.html"
cp "$REPO_ROOT/site/style.css"  "$SITE_OUT/style.css"
cp "$BUILD_DIR/mars.jsdos"      "$SITE_OUT/mars.jsdos"
cp "$BUILD_DIR/MARS.COM"        "$SITE_OUT/MARS.COM"
cp "$REPO_ROOT/MARS.ASM"        "$SITE_OUT/MARS.ASM"
cp "$REPO_ROOT/mars_4_3.png"    "$SITE_OUT/mars_4_3.png"
cp -R "$BUILD_DIR/js-dos"       "$SITE_OUT/js-dos"

# GitHub Pages runs Jekyll by default, which strips paths beginning with a
# dot and can mangle asset directories. .nojekyll turns that off.
touch "$SITE_OUT/.nojekyll"

log "Site ready in $SITE_OUT ($(du -sh "$SITE_OUT" | cut -f1))"
```

- [ ] **Step 6: Run the tests and make sure they pass**

Run: `chmod +x scripts/build-site.sh && bash tests/test-site.sh`
Expected: PASS — 13 assertions, 0 failures.

(Count check: 1 `assert_success`, 7 `assert_file_exists`, 4 `assert_contains`,
1 third-party branch = 13.)

- [ ] **Step 7: Commit**

```bash
git add site/index.html site/style.css scripts/build-site.sh tests/test-site.sh
git commit -m "site: add js-dos player page and site composition script"
```

---

### Task 6: Local preview server and Makefile

**Files:**
- Create: `scripts/serve.sh`
- Create: `Makefile`

**Interfaces:**
- Consumes: all scripts from Tasks 2–5.
- Produces: `make build|bundle|site|serve|test|clean` targets. Nothing downstream depends on these.

- [ ] **Step 1: Write the preview server**

Create `scripts/serve.sh`:

```bash
#!/usr/bin/env bash
# Builds the site and serves it over HTTP.
#
# HTTP rather than file:// is required: js-dos loads mars.jsdos with fetch(),
# and browsers block fetch on file:// origins.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

port="${PORT:-8080}"

bash "$REPO_ROOT/scripts/build-site.sh"

need python3
log "Serving $SITE_OUT at http://localhost:$port  (Ctrl-C to stop)"
cd "$SITE_OUT"
exec python3 -m http.server "$port"
```

- [ ] **Step 2: Write the Makefile**

Create `Makefile`:

```makefile
# Thin wrappers over scripts/. Every target is also runnable directly.
.PHONY: all build bundle jsdos site serve test clean

all: site

build:   ## Assemble MARS.ASM into build/MARS.COM
	@bash scripts/build.sh

bundle: build   ## Package build/mars.jsdos for js-dos
	@bash scripts/bundle.sh

jsdos:   ## Fetch the pinned js-dos assets
	@bash scripts/fetch-jsdos.sh

site:   ## Compose the deployable site into _site/
	@bash scripts/build-site.sh

serve:   ## Build the site and serve it at http://localhost:8080
	@bash scripts/serve.sh

test:   ## Run the test suite
	@bash tests/run-tests.sh

clean:   ## Remove build outputs (keeps the cached toolchain)
	@rm -rf build _site
	@echo "Removed build/ and _site/ (run 'rm -rf .toolchain' to drop the assembler too)"
```

- [ ] **Step 3: Verify the targets work**

Run: `make clean && make site && bash tests/run-tests.sh`
Expected: `_site/` rebuilt; all test files pass.

- [ ] **Step 4: Verify the demo actually renders**

Run: `make serve`, then open <http://localhost:8080> in a browser.

Confirm all four, and do not proceed until they hold:
1. The landscape draws (orange/brown terrain against a graded sky).
2. Colours look correct — a washed-out or wrongly-shaded palette means
   `machine=vgaonly` is not being applied; check the conf inside the bundle.
3. Moving the mouse after clicking the canvas pans the camera.
4. The browser network panel shows **no** requests to any origin other than
   `localhost`.

If js-dos reports a missing emulator asset, `pathPrefix` is wrong: it must be
`js-dos/emulators/`, with the trailing slash.

- [ ] **Step 5: Commit**

```bash
git add scripts/serve.sh Makefile
git commit -m "build: add local preview server and Makefile targets"
```

---

### Task 7: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `scripts/build.sh --check`, `tests/run-tests.sh`.
- Produces: a `MARS.COM` workflow artifact on every push and pull request.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: Build MARS.COM

on:
  push:
    branches: ["**"]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache the JWasm toolchain
        uses: actions/cache@v4
        with:
          path: .toolchain
          key: jwasm-${{ hashFiles('versions.env') }}

      - name: Assemble MARS.COM and verify reproducibility
        run: bash scripts/build.sh --check

      - name: Run the test suite
        run: bash tests/run-tests.sh

      - name: Report size and checksum
        run: |
          size=$(wc -c < build/MARS.COM | tr -d ' ')
          sha=$(sha256sum build/MARS.COM | cut -d' ' -f1)
          {
            echo "### MARS.COM"
            echo ""
            echo "| | |"
            echo "|---|---|"
            echo "| Size | $size bytes |"
            echo "| SHA-256 | \`$sha\` |"
          } >> "$GITHUB_STEP_SUMMARY"

      - uses: actions/upload-artifact@v4
        with:
          name: MARS.COM
          path: build/MARS.COM
          if-no-files-found: error
```

- [ ] **Step 2: Commit and push, then verify the run is green**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: verify MARS.COM builds reproducibly on every push"
git push -u origin feat/jsdos-pages-build
```

Then: `gh run watch` (or `gh run list --limit 1`).
Expected: the workflow completes successfully and the summary shows
1550 bytes with the pinned SHA-256.

If the run does not appear at all, Actions is disabled on the fork — enable it
with `gh api repos/dtz-labs/MARS.COM/actions/permissions -X PUT --input - <<< '{"enabled":true,"allowed_actions":"all"}'`.

---

### Task 8: Pages workflow and repository configuration

**Files:**
- Create: `.github/workflows/pages.yml`

**Interfaces:**
- Consumes: `scripts/build-site.sh`.
- Produces: a deployed GitHub Pages site at `https://dtz-labs.github.io/MARS.COM/`.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/pages.yml`:

```yaml
name: Deploy Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

# Let a running deploy finish rather than cancelling it mid-flight.
concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Cache the JWasm toolchain
        uses: actions/cache@v4
        with:
          path: .toolchain
          key: jwasm-${{ hashFiles('versions.env') }}

      - name: Build the site
        run: bash scripts/build-site.sh

      - uses: actions/configure-pages@v5

      - uses: actions/upload-pages-artifact@v3
        with:
          path: _site

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: Point Pages at GitHub Actions**

Forks do not inherit Pages settings, so set the source explicitly:

```bash
gh api repos/dtz-labs/MARS.COM/pages -X POST --input - <<< '{"build_type":"workflow"}' \
  || gh api repos/dtz-labs/MARS.COM/pages -X PUT --input - <<< '{"build_type":"workflow"}'
gh api repos/dtz-labs/MARS.COM/pages --jq '{status,html_url,build_type}'
```

Expected: `build_type` is `workflow`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/pages.yml
git commit -m "ci: build and deploy the js-dos player to GitHub Pages"
```

---

### Task 9: README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing. Terminal task.
- Produces: nothing.

- [ ] **Step 1: Rewrite the README**

Replace `README.md` with the content below. It keeps upstream's text and
credits intact and adds only what this fork contributes. Note the byte-count
paragraph: upstream claims 1517 bytes, our reproducible build is 1550 — the
discrepancy is stated rather than papered over.

```markdown
# MARS landscape

A comprehensive study of the outstanding code example from 1993 — the martian
landscape renderer by Tim J. Clarke.

Original code has been disassembled, rewritten and reduced from **5649** bytes
to about **1.5 kB** by [Wojciech Bruzda](https://github.com/matrix-toolbox).

**Tim, if you read this, please contact
[upstream](https://github.com/matrix-toolbox/MARS.COM)!**

![MARS](mars_4_3.png)

## ▶ Run it in your browser

**<https://dtz-labs.github.io/MARS.COM/>**

Click the canvas to capture the mouse — moving it pans the camera.

## What this fork adds

Upstream ships the annotated assembly only. This fork adds a reproducible
build and a browser player:

- `scripts/build.sh` — assembles `MARS.ASM` into `MARS.COM`
- `scripts/build-site.sh` — composes the GitHub Pages site
- GitHub Actions workflows that verify the build and deploy the page

`MARS.ASM` remains the single source of truth; the binary is never committed.

## Building

```sh
make build     # assemble build/MARS.COM
make serve     # build the site and preview at http://localhost:8080
make test      # run the test suite
```

`MARS.ASM` is MASM/TASM dialect (`.model tiny`, `org 100h`, `COMMENT #`
blocks), so it needs a MASM-compatible assembler — NASM cannot build it. The
build uses [JWasm](https://github.com/Baron-von-Riedesel/JWasm), pinned in
`versions.env`. If no assembler is on your `PATH`, `build.sh` compiles JWasm
from source into `.toolchain/` automatically. With no C compiler available,
`bash scripts/build.sh --docker` runs the whole build in a container.

### Build output

The pinned toolchain produces a **1550-byte** `MARS.COM`
(`sha256:10a1bb6c…`), byte-identical under JWasm v2.20 and v2.21. Upstream's
README reports **1517** bytes; the 33-byte difference comes from the original
author's toolchain and has not been reconciled. `scripts/build.sh --check`
enforces the 1550-byte result so unintended changes to `MARS.ASM` are caught.

## Running it natively

It works on DOSBox and on genuine x86 machines (a mouse is needed). Under
DOSBox, always use `-machine vgaonly` — the renderer drives VGA mode 13h and
reprograms the palette DAC, and the default `svga_s3` emulation shows
artifacts. More details are on the
[author's page](https://chaos.if.uj.edu.pl/~wojtek/MARS.COM).

## Credits and licence

- Original martian landscape renderer — **Tim J. Clarke**, 1993
- Disassembly, rewrite and size reduction — **Wojciech Bruzda**, 2021
- Browser emulation — [js-dos](https://js-dos.com), pinned in `versions.env`

Released under GPL-3.0, as upstream.
```

- [ ] **Step 2: Verify links resolve**

Run: `grep -oE 'https?://[^)]+' README.md`
Check each host is reachable and that the Pages URL matches the one reported
by `gh api repos/dtz-labs/MARS.COM/pages --jq .html_url`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document the build, the player, and the byte-count discrepancy"
```

---

## Final verification

After all tasks, before merging to `main`:

- [ ] `make clean && rm -rf .toolchain && make test` passes from a cold start
- [ ] `make serve` renders the demo correctly (terrain, palette, mouse)
- [ ] `gh run list --limit 3` shows CI green
- [ ] Merge to `main`, then confirm the Pages deploy succeeds and
      <https://dtz-labs.github.io/MARS.COM/> loads with no third-party requests
