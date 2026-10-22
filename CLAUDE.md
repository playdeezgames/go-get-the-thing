# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## State of the repo

`DESIGN.md` is the plan (it now ends with the pivot to an incremental game; read that section first); `world.json` and `game_tags.json` are exported from the Anvil (do not hand-edit `world.json`). Code: `game/` (platform-independent logic and drawing, with tests) and `app/` (`make_tool`, the Tool the Anvil's frontends drive; see the Anvil's `GAMES.md`). The game is becoming an incremental one (`DESIGN.md`, last section): steps 1 to 4 are done (content authored, upgrade model and save, run/shop state machine and shop screen, helpers in `game/helpers.odin`); balancing (step 5) is done by simulation (see the end of `DESIGN.md`; `./build.sh test -define:SIM=true ...`); playing it is the real test. Earlier steps: rules (movement, pickup, respawn, timer on `update`, title and game-over states), a minimal HUD and the title/game-over text. Mouse input is an on-screen pad (`game/pad.odin`: four arrows and a green button in the strip below the 20x10 room; a held direction repeats), not click-a-cell. Native and a real gamepad are verified (the pad needs read access to its /dev/input/event node: the `input` group). The HUD (score and time) sits in the pad strip (`game/hud.odin`). The Thing only respawns where the player can walk (`game/reach.odin`). Web polish is still to do.

```bash
./build.sh test     # odin test game (needs -collection:anvil, passed for you)
./build.sh check    # odin check game (native + js_wasm32), then builds native and web
./build.sh run      # build and run natively (the Anvil's build.sh with APP_DIR=app, output in build/)
./build.sh serve 8123   # web build + local server
```

`ANVIL_DIR` overrides the Anvil repo location. The game imports the Anvil only as `anvil:common` and `anvil:anvil_runtime`.

"Go Get the Thing!" is a deliberately tiny demo game whose purpose is to practise making a game with the **Anvil of SPLORR!!**. A character moves in a room with exterior and interior walls; touching the "Thing" picks it up for a point; a countdown timer ends the game and shows the final score. `DESIGN.md` says what to author in the Anvil and how the game is built on it.

## Related repos (added as working directories)

- `/home/yermom/git/anvil-of-splorr`: the asset tool suite (Odin, SDL2 native + `js_wasm32` web). Its `world.json` format (`common/world.odin`; spec in its `WORLD.md`) is where this game's palette, tiles, terrains, sprites, characters and map come from. **The game imports its `anvil_runtime` package** (load a world, tags, `Play_State` for moving characters without touching the world, drawing, `param_number`/`param_text`, `required_missing`) and embeds `world.json` with `#load`; a `World` is ~21 MB (global or `new()`, never by value). The Anvil has characters (uuid table; `World.player`), tags (`solid` built in; the game needs `thing` and `spawn`, declared in a `game_tags.json`), game parameters and a play mode, but no sound. When the game needs something the Anvil lacks, tell the user (they direct the Anvil session through its `USER_STORIES.md`) rather than faking the asset by hand-editing `world.json`. Read its `CLAUDE.md` before writing code here: it defines the frontend/renderer split, the eight-command input model (keyboard, gamepad and mouse must all work; on-screen command names go through `action_label`), the 320x180 logical surface, and Odin build conventions (`./build.sh check|test|run|web`, every `*_test.odin` needs `#+build !js`).
- `/home/yermom/git/bok-of-splorr`: an Obsidian vault of the user's SPLORR!! knowledge (Odin wasm recipe, Gotchas, Release standard). Notes only; do not edit unless asked. Rules there to honour: never `git push` or run ship/publish scripts unless the user says so explicitly.

## Working rules

- Game logic (state, timer, score, collision, spawning) should stay platform-independent, with only a thin renderer/input layer per frontend, mirroring the Anvil's architecture so the game can run native and on the web.
- `world.json` is produced by the Anvil's editors; treat it as an input asset. Do not regenerate or overwrite the user's `world.json`, `input_map.json` or `default-font.json` in the Anvil repo.
- Odin is at `/home/yermom/.local/bin/odin`.
