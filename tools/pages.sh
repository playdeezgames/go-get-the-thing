#!/bin/bash
# Builds the GitHub Pages site: tests, an optimized web build, copied into docs/. Never commits, never pushes.
# Usage: tools/pages.sh   (then commit docs/ and, when told to, git push)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build/web/go_get_the_thing"

./build.sh test
WEB_OPT=size ./build.sh web
rm -rf docs
mkdir docs
cp -rL "$OUT"/. docs/
touch docs/.nojekyll
echo "docs/ ready ($(du -sh docs | cut -f1)). Site: https://playdeezgames.github.io/go-get-the-thing/"
