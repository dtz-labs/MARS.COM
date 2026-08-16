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
