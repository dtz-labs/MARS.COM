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
