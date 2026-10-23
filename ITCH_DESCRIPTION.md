# Itch.io page text

Page: https://thegrumpygamedev.itch.io/go-get-the-thing
Pasted in by hand; nothing here is published by the repo.

## Short description

A tiny incremental game: run around a walled room, go get the Thing, spend the coins, and get a little faster each time.

## Paste this as the page description

Go get the Thing!

You are a small blue person in a walled room with one glowing Thing. Walk onto it and it pays out coins, then turns up somewhere else. When the clock runs out the run is over, and you spend what you earned in the shop.

Buy a higher Thing value, longer runs, more Things in the room and faster feet. Buy helpers who go and get Things for you, and make them quicker too. The early runs are slow. Later ones are a blur of helpers.

When the upgrades start to crawl, **prestige**: trade the era's coins for gems, start over, and spend the gems on perks that make the next era faster. A time bonus chance adds seconds when a Thing is picked up, and lucky coins pays out five times as much.

**Controls:** arrow keys to move, Space to select, Escape to start a run from anywhere in the shop. A gamepad works too: the d-pad to move (hold a direction and you keep walking), A to select, B to start a run. The on-screen buttons work with a mouse or touch, though the keyboard or a pad suits the game better.

**Saving:** the game saves itself in yer browser after every run and purchase. Clear yer site data and it is gone.

Made with the Anvil of SPLORR!!, TheGrumpyGameDev's own asset tools: the art, the sounds and the room all come from it. The game was written with Claude Code (generative AI).

## Notes (not for the page)

- Push target: `thegrumpygamedev/go-get-the-thing:html` (pushed October 23, 2026, build 2191917). `tools/ship.sh` builds and zips; it only pushes with `--push`.
- On the page's Edit game screen: "Kind of project" HTML, "This file will be played in the browser" ticked, and an embed of 960 by 540 (the game is 320 by 180 and scales to fit).
- The cover is `assets/cover.png` (630 by 500) and the screenshots are in `assets/screenshots/`, both made by `tools/make_cover.py` from raw 320 by 180 captures of the web build.
- The page text discloses that the game was written with Claude Code. If the edit screen has a generative-AI disclosure field, fill it in to match.
