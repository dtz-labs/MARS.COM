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
