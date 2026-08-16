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
