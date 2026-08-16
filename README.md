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

On macOS the JWasm build needs two portability fixes (its makefile targets
Linux/FreeBSD); `build.sh` applies them automatically.

### Build output

The pinned toolchain produces a **1550-byte** `MARS.COM`
(`sha256:10a1bb6c…`), byte-identical under JWasm v2.20 and v2.21 and across
macOS/clang/ARM64 and Linux/gcc. Upstream's README reports **1517** bytes; the
33-byte difference comes from the original author's toolchain and has not been
reconciled. `scripts/build.sh --check` enforces the 1550-byte result so
unintended changes to `MARS.ASM` are caught.

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
