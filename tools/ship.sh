#!/bin/bash
# Prepares the itch.io build: tests, an optimized web build, a zip. Pushes ONLY with --push. Never commits, never deletes
# anything but its own zip. Usage: tools/ship.sh [--push]
set -euo pipefail
cd "$(dirname "$0")/.."
# The page: https://thegrumpygamedev.itch.io/go-get-the-thing
TARGET="thegrumpygamedev/go-get-the-thing:html"
OUT="build/web/go_get_the_thing"
ZIP="build/go-get-the-thing-html5.zip"

./build.sh test
WEB_OPT=size ./build.sh web
rm -f "$ZIP"
(cd "$OUT" && zip -q -9 -r "../../go-get-the-thing-html5.zip" .)
echo "zip: $ZIP ($(du -h "$ZIP" | cut -f1)); wasm $(du -h "$OUT/app.wasm" | cut -f1)"
unzip -l "$ZIP" | tail -8

if [ "${1:-}" = "--push" ]; then
	if [ -n "$(git status --porcelain)" ]; then echo "note: the working tree has uncommitted changes; what is pushed is the working tree, not a commit"; fi
	butler push "$ZIP" "$TARGET"
	echo "pushed to $TARGET. It goes live after itch.io processes it; check: butler status $TARGET"
else
	echo "not pushed (run tools/ship.sh --push when you want it live; the target is $TARGET)"
fi
