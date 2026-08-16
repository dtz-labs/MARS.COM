# MARS.COM — build scripts and js-dos GitHub Pages player

**Date:** 2026-08-16
**Repo:** `dtz-labs/MARS.COM` (fork of `matrix-toolbox/MARS.COM`, GPL-3.0)
**Status:** revision 2 — shipped and visually confirmed

---

## Revision 2: js-dos replaced by v86

**Everything below this section describing js-dos is superseded.** It is kept
as the decision record rather than rewritten, because the reason for the change
is more useful than a tidy document.

**What happened.** The js-dos player crashed repeatedly in Firefox with
`Backend crashed, cause: ...`. That string comes from `wdosbox.js`, the
Emscripten DOSBox module's exception handler, which fires on any uncaught
exception in the wasm DOSBox other than a clean `exit(0)`. So the DOSBox core
itself was throwing — not the page, not the bundle, not our configuration.

**Why not another DOSBox wrapper.** js-dos, em-dosbox, DOSee and Emularity all
wrap the same DOSBox core. Switching between them would have reproduced the
same crash. Only emulators that emulate *hardware* rather than the DOS API have
genuinely different failure modes.

**What replaced it.** [v86](https://github.com/copy/v86) (BSD), pinned to
0.5.432, emulating a full PC. The page boots the 720 KB FreeDOS floppy used by
v86's own demos, with `MARS.COM`, CuteMouse and an `AUTOEXEC.BAT` injected at
build time via `mtools`.

**The non-obvious consequence.** MARS calls `int 33h` (`MARS.ASM:122`, `:388`).
DOSBox implements that service internally; hardware emulation does not. A
resident DOS mouse driver therefore became a hard requirement of the new
design. MARS checks for the driver (`setz` at `:124`, tested at `:385`) and
degrades gracefully, so a missing driver costs camera control rather than the
whole demo — which makes the mouse an independently testable step, not a
prerequisite for first render.

**Superseded components.** `scripts/bundle.sh` and `scripts/fetch-jsdos.sh` are
gone, replaced by `scripts/make-image.sh` and `scripts/fetch-v86.sh`. The
`.jsdos` bundle is replaced by a bootable floppy image. Building the site now
requires `mtools`.

**Supply-chain note.** Every third-party download — v86 runtime, both BIOS
blobs, the FreeDOS image, the mouse driver — is pinned by SHA-256, and the BIOS
blobs are pinned to an immutable commit rather than a branch, since they are
executed by the emulator.

**Verification.** The build is verified by CI on Linux and reproduces
byte-identically on macOS. The rendered demo was confirmed visually in a real
browser on 2026-08-16.

---

## Purpose

The upstream repository ships the MARS landscape renderer as assembly source
only. There is no binary, no build instructions, and no way to see the demo
without a DOS machine or a local DOSBox install.

This project adds two things:

1. A reproducible build that turns `MARS.ASM` into a runnable `MARS.COM`.
2. A GitHub Pages site that runs that binary in the browser via js-dos, so the
   demo can be seen by clicking a link.

## Background

`MARS.ASM` is a 778-line MASM/TASM-dialect source: `.model tiny`, `.code`,
`.386`, `org 100h`, `end start`. Two lines that look like corruption (bare `#`
at lines 615 and 777) are MASM `COMMENT #` block delimiters around a disabled
jump-table dispatch. The dialect is not NASM-compatible and cannot be ported
without a rewrite.

Because the model is tiny, the assembler emits a `.COM` memory image directly.
No linker or `exe2bin` step is required.

The source comments record two runtime requirements: DOSBox must run with
`-machine vgaonly`, and the demo needs a mouse (it drives the camera). The
`vgaonly` requirement is about rendering correctness, not preference — the
renderer writes to VGA mode 13h and reprograms the palette DAC, and DOSBox's
default `svga_s3` emulation produces visual artifacts.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Repo relationship | True GitHub fork | Preserves upstream attribution link; allows upstream PRs |
| Assembler | JWasm, pinned version | MASM-compatible, open source, builds from source with gcc |
| Built binary | CI-only, never committed | `MARS.ASM` stays the single source of truth |
| js-dos delivery | Downloaded at Pages build time, pinned version | Self-hosted at runtime, lean repo, reproducible |
| js-dos version | 8.4.1 | Current release; verified self-hostable |
| Emulator backend | `dosbox` (`wdosbox`) | 1.5 MB vs 7.9 MB for dosbox-x; `vgaonly` is supported |
| Page scope | Framed player plus context | Credits, usage hint, size story, source and download links |

## Verified findings

These were established by direct investigation, not assumption:

- JWasm 2.21 assembles `MARS.ASM` cleanly: 778 lines, 3 passes, 0 warnings,
  0 errors, producing a **1550-byte** `MARS.COM`. The upstream README claims
  1517 bytes; the discrepancy is documented rather than hidden.
- js-dos 8.4.1's `dist/` contains **no** references to `SharedArrayBuffer` or
  `crossOriginIsolated`. It therefore does not require COOP/COEP headers, which
  GitHub Pages cannot set. Self-hosting on Pages is viable.
- `js-dos.js` contains no hardcoded absolute base path. The CDN URL appears only
  as a default for the `pathPrefix` option, which we override.
- The js-dos npm tarball (14 MB) contains `dist/js-dos.js`, `dist/js-dos.css`,
  and `dist/emulators/*`. Only a subset is needed for this deployment.

## Architecture

### Components

**`versions.env`** — the single source of truth for every pin: JWasm tag, js-dos
version, the expected `MARS.COM` size and SHA-256, and the `.COM` size ceiling.
Plain `KEY=value` so both shell scripts and CI can read it.

**`scripts/lib.sh`** — sourced by every script. Sets `set -euo pipefail`, derives
the repo paths, loads `versions.env`, and provides `log`, `die`, and `need`.

**`tests/`** — a dependency-free bash test harness (`tests/lib.sh` assertions,
`tests/run-tests.sh` runner) with one test file per script.

**`scripts/build.sh`** — assembles `MARS.ASM` into `MARS.COM`.

Resolves a toolchain in order: `$JWASM` environment variable, then `jwasm` on
`PATH`, then builds JWasm from a pinned upstream tag into `.toolchain/`. A
`--docker` flag runs the whole build in a container for hosts with no compiler.
The same script runs locally and in CI, so the two cannot drift.

Output: `build/MARS.COM`.

**`scripts/bundle.sh`** — produces the js-dos bundle.

Creates `build/mars.jsdos`, a ZIP containing `MARS.COM` and `.jsdos/dosbox.conf`.
The config pins `machine=vgaonly`, enables mouse autolock, and autoexecs the
program.

**`scripts/fetch-jsdos.sh`** — downloads the pinned js-dos release.

Fetches the js-dos npm tarball at the pinned version, extracts only the files
the page needs (`js-dos.js`, `js-dos.css`, `emulators/emulators.js`,
`emulators/wdosbox.js`, `emulators/wdosbox.wasm`), and places them under the
site output. Never runs at page-view time.

**`scripts/build-site.sh`** — assembles the deployable site.

Composes `site/` sources, the built `MARS.COM`, the `.jsdos` bundle, and the
fetched js-dos assets into `_site/`.

**`scripts/serve.sh`** — local preview.

Builds the site and serves `_site/` over HTTP. HTTP rather than `file://` is
required because bundle loading uses `fetch`.

**`Makefile`** — thin targets over the scripts: `build`, `bundle`, `site`,
`serve`, `clean`.

### Site

Static HTML and CSS, no framework, no build step beyond file composition.

`site/index.html` frames the js-dos canvas with:

- Credit to Tim J. Clarke (original, 1993) and Wojciech Bruzda (disassembly and
  reduction, 2021)
- A usage hint: click to capture the mouse; the mouse drives the camera
- The size story: 5649 bytes reduced to roughly 1.5 KB
- Links to `MARS.ASM`, the `MARS.COM` download, and the upstream repository

js-dos is initialised with `pathPrefix` pointing at the self-hosted emulator
directory, `backend: "dosbox"`, and `url` pointing at `mars.jsdos`.

### Workflows

**`.github/workflows/ci.yml`** — on push and pull request.

Runs `scripts/build.sh --check`, which asserts the output is non-empty, within
the `.COM` ceiling, and byte-identical to the pinned size and SHA-256. Also
records size and SHA-256 in the job summary. Uploads `MARS.COM` as a workflow
artifact.

**`.github/workflows/pages.yml`** — on push to `main` and manual dispatch.

Builds the binary, fetches pinned js-dos, assembles the site, uploads a Pages
artifact, and deploys. Requires `pages: write` and `id-token: write`.

### Repository configuration

Two settings are applied via the GitHub API, since forks do not inherit them:

- GitHub Actions enabled on the fork
- Pages source set to `github-actions`

## Data flow

```
MARS.ASM ──[JWasm -bin]──> build/MARS.COM ──┐
                                            ├──[zip]──> build/mars.jsdos ──┐
.jsdos/dosbox.conf ─────────────────────────┘                              │
                                                                           ├──> _site/ ──> Pages
site/index.html, site/style.css ───────────────────────────────────────────┤
                                                                           │
js-dos 8.4.1 npm tarball ──[fetch, extract subset]──> _site/js-dos/ ───────┘
```

At page view time nothing is fetched from outside the Pages origin.

## Error handling

- **Assembler unavailable.** `build.sh` falls back through its toolchain chain
  and fails with an explicit message naming the options, rather than a bare
  `command not found`.
- **Assembly failure.** JWasm's non-zero exit fails the build; its diagnostics
  are surfaced verbatim. CI does not deploy a stale binary.
- **Size regression.** `build.sh` fails if the output is empty or exceeds
  **65280 bytes** (0xFF00 — the true `.COM` ceiling, since the PSP occupies the
  first 256 bytes of the segment), which would mean the tiny-model assumption
  has broken.
- **Unintended source change.** `build.sh --check`, which CI runs, fails if the
  binary no longer matches the pinned size and SHA-256. A deliberate change to
  `MARS.ASM` must update `versions.env` in the same commit, making it visible in
  review rather than silent.
- **js-dos fetch failure.** The Pages build fails rather than deploying a page
  with missing emulator assets.
- **Browser-side load failure.** The page shows an inline error message instead
  of an indefinitely blank canvas.

## Testing

- `scripts/build.sh` produces a `MARS.COM` of the expected size, from a clean
  checkout, on a machine with no assembler pre-installed.
- The same script succeeds in CI on `ubuntu-latest`.
- `scripts/serve.sh` renders the demo locally: the landscape draws, the palette
  is correct, and mouse movement pans the camera.
- The deployed Pages URL loads with no requests to third-party origins
  (verifiable in the browser network panel).

## Out of scope

- Modifying `MARS.ASM` itself
- Mobile or touch controls
- Reconciling the 1517-byte figure by reproducing the author's original
  toolchain; the discrepancy is documented, not resolved
- Upstreaming the build to `matrix-toolbox`
