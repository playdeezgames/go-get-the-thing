#!/usr/bin/env bash
# Usage: ./build.sh <check|test|native|run|web|serve> [args]
# The game is only an app/ package and a game/ package; the Anvil supplies the frontends (its GAMES.md).
# ANVIL_DIR = the Anvil repo (default /home/yermom/git/anvil-of-splorr).
set -euo pipefail
cd "$(dirname "$0")"
here="$PWD"
anvil="${ANVIL_DIR:-/home/yermom/git/anvil-of-splorr}"
coll="-collection:anvil=$anvil"
target="${1:-test}"
[ $# -gt 0 ] && shift
case "$target" in
	check)
		odin check game -no-entry-point $coll
		odin check game -no-entry-point -target:js_wasm32 $coll
		"$0" native && "$0" web ;;
	test)   odin test game $coll "$@" ;;
	native|run|web|serve)
		APP_DIR="$here/app" APP_NAME=go_get_the_thing OUT_DIR="$here/build" "$anvil/build.sh" "$target" "$@" ;;
	*) echo "unknown target: $target (check, test, native, run, web, serve)" >&2; exit 2 ;;
esac
