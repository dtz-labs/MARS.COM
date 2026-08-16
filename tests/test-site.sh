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
