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

# wlibzip is not optional: js-dos unpacks the .jsdos bundle (a ZIP) with it
# at runtime, and without it the emulator 404s before DOS ever boots.
tar xzf "$tarball" -C "$work" \
  package/dist/js-dos.js \
  package/dist/js-dos.css \
  package/dist/emulators/emulators.js \
  package/dist/emulators/wdosbox.js \
  package/dist/emulators/wdosbox.wasm \
  package/dist/emulators/wlibzip.js \
  package/dist/emulators/wlibzip.wasm \
  || die "js-dos tarball did not contain the expected dist layout"

cp "$work/package/dist/js-dos.js"  "$dest/js-dos.js"
cp "$work/package/dist/js-dos.css" "$dest/js-dos.css"
cp "$work/package/dist/emulators/emulators.js" "$dest/emulators/emulators.js"
cp "$work/package/dist/emulators/wdosbox.js"   "$dest/emulators/wdosbox.js"
cp "$work/package/dist/emulators/wdosbox.wasm" "$dest/emulators/wdosbox.wasm"
cp "$work/package/dist/emulators/wlibzip.js"   "$dest/emulators/wlibzip.js"
cp "$work/package/dist/emulators/wlibzip.wasm" "$dest/emulators/wlibzip.wasm"

rm -rf "$work"

log "js-dos $JSDOS_VERSION staged in $dest ($(du -sh "$dest" | cut -f1))"
