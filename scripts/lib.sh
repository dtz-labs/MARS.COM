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
