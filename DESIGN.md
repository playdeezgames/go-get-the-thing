# Go Get the Thing!: design

The game: a character in a walled room (exterior and interior walls) and a "Thing". Walking onto the Thing picks it up, scores a point, and the Thing appears somewhere else. A timer counts down; at zero the game ends and the final score is shown.

"Anvil" means `/home/yermom/git/anvil-of-splorr` at commit `f92ea49` or later. Its spec is `WORLD.md`; the game-side API is the `anvil_runtime` package (`anvil_runtime/world.odin`, `play.odin`). All the gaps this game originally had (placing entities, role tags, spawn points, runtime library, drawing, game parameters, tag requirements, web loading) are closed; sound has since been added (PLAY text sounds in the world).

## Content to author in the Anvil (`world.json`)

| What | How |
|---|---|
| Palette, tile size | World-wide: 16 colours, one tile size (16x16 gives 20x11 tiles on the 320x180 surface) |
| Floor and wall images | Tileset images |
| Terrains | `floor`, `wall`. `wall` carries the built-in tag `solid` |
| The room | One map, 20x10 (fits one screen with a 20-pixel strip below for the on-screen pad: no scrolling), outer wall plus interior walls |
| Tags | `solid` (built in), `thing`, `spawn` |
| Player | A character type `player` (with a sprite); one character of it placed on a floor cell and set as the world's player |
| The Thing | A character type carrying the tag `thing`; one character of it placed on a floor cell |
| Where the Thing may appear | Tag `spawn` on floor cells (per-cell tags in the map editor) or on a terrain |
| Parameters | Whole numbers `round_seconds` and `points_per_thing`; the game gives defaults if absent |
| Sound | Two PLAY-text sounds, `pickup` (a rising jingle) and `game_over` (a falling tune), played through the Tool's `take_audio` hook on channel 0; WAV copies for listening are in `sounds/` |

Ship `game_tags.json` beside the game and the Anvil's world editor: `{"tags": [{"name": "thing", "note": "what the player picks up"}, {"name": "spawn", "note": "cells the Thing may appear on"}]}`. The TAGS screen then marks them NEEDED / MISSING and CREATE adds the missing ones. The game checks the same list at start-up.

Tag effective values: a character type or terrain has a tag or not; a character or a cell inherits it, or sets/clears it. Always ask through the runtime (`cell_has_tag`, `cell_is_solid`, `character_has_tag`), never the terrain alone.

## Game structure (all in this repo, on `anvil_runtime`)

1. **Start-up**: embed the world with `WORLD_FILE :: #load("world.json")` (native and web alike, no file-size limit), then `rt.load(world, WORLD_FILE)` into a `rt.new_world()` or a global (a `World` is ~21 MB, never by value). Stop with the error text if it fails. Then parse the embedded `game_tags.json` (`rt.parse_game_tags`) and stop with `rt.required_missing` if it lists anything. Resolve `solid` (`rt.TAG_SOLID`), `thing` and `spawn` with `rt.find_tag`. Read parameters with `rt.param_number(world, "round_seconds", default)` and `"points_per_thing"`.
2. **Actors**: the player is `rt.player(world)`; the Thing is the character where `rt.character_has_tag(world, ci, thing_tag)`. Take the first one as the target (several would also work as pickups).
3. **Runtime state**: a `rt.Play_State` (copyable, ~32 KB) built with `rt.play_init`; the game moves characters only through it and never changes the world. "Play again" is another `play_init`. Plus the game's own score, time left and state.
4. **Movement**: `rt.play_step(&ps, world, player, dx, dy)`, one cell per press. It refuses (`Move_Result`) the map edge, solid cells and cells holding another character. Because the Thing is a character, a step onto it returns `.Occupied`; before stepping, check `rt.play_character_at` for the target cell, and if it is the Thing, treat it as a pickup (below).
5. **Pickup**: if the target cell holds the Thing, add `points_per_thing` to the score, `rt.play_unplace` the Thing, step the player in, then respawn.
6. **Respawn**: candidates = `rt.cells_with_tag(world, map, spawn_tag)` minus solid cells and the player's cell (and optionally cells not reachable from the player by flood fill over non-solid cells). Pick one with the game's RNG and `rt.play_place` the Thing there. If there are no candidates, show a clear message at start-up rather than guessing.
7. **State machine and timer**: Title -> Playing -> Game over (final score; a command to play again). The timer counts down from `round_seconds` in frame-step time.
8. **Random source**: seedable RNG (the wasm RNG quirk is in `bok-of-splorr/splorr/Gotchas.md`).
9. **Drawing**: per frame, `rt.zoom_window(world, map, 0, 0, 20, 11, 0, 0, 1)` then `rt.draw_terrain` and `rt.draw_characters(&r, world, &ps, window)` on the Anvil's `Renderer`. The characters are drawn from the `Play_State`, so they appear where they are now. Set `window.mark_player` only if the author wants the corner mark. Leave room for the HUD (the 20x11 room at zoom 1 uses 320x176 of 180 rows, so draw the HUD as an overlay on the wall rows or use a smaller room such as 20x10).
10. **HUD and screens**: score and time with the UI font (`draw_text`), title and game-over screens. Any on-screen text that names a command goes through `action_label`.
11. **Input**: the Anvil's eight commands and `input_map.json`: keyboard, gamepad and mouse all work (mouse: an on-screen pad below the room, see `game/pad.odin`; clicking cells was dropped as awkward).
12. **Frontends**: native SDL2 and web (`js_wasm32`) as an Anvil-style app: game logic platform-independent, frontends only draw and translate input. For the web either embed (preferred) or `WEB_FETCH=world.json ./build.sh web <app>`.

## Things to decide when building

- Step per press, or repeat while a direction is held.
- Whether the HUD overlays the room or the room is made 20x10.
- Whether the pickup is detected by `.Occupied` or by looking at the target cell first (the latter is what `play_step`'s own comment suggests).
- Whether to test the reachability of spawn cells.
- Where the game's code lives (a `game/` package with `*_test.odin` files carrying `#+build !js`) and how it is built (an app entry like the Anvil's `apps/<name>`).

## Remaining Anvil gaps

- **Play mode does not show `spawn` cells**: check them on the map editor's cell Tags screen.
- Tag names `thing` and `spawn` remain a convention, now enforced by `game_tags.json` and `rt.required_missing`.

## Pivot: an incremental game (decided October 22, 2026)

The plain "collect for points" round is not much of a game, so it becomes an incremental one. The room, sprites, sounds, pad, HUD and the reachability check stay; what changes is what the score is for.

**Loop.** A *run* is the timed round we have: walk onto the Thing, earn coins, the clock runs out. Coins are a currency that is kept. Between runs a **shop** screen spends them on permanent upgrades, then the next run starts. Upgrades bring in helpers that collect for you, so play moves from steering to buying ("walk and collect, then automate").

**Upgrades** (each has a level and a cost that grows with it; start with these five, tune in play):

| Upgrade | Effect |
|---|---|
| Thing value | more coins per Thing |
| Run length | more seconds per run |
| Helpers | up to N helper characters that walk to the nearest Thing and pick it up |
| Helper speed | helpers step faster |
| More Things | up to M Things in the room at once |
| Player speed | the player may step faster (the base rate is limited so this matters) |

**State.** Title -> Run -> Shop -> Run -> ... (a run ends at zero; the shop shows the coins just earned and the total). Saved: coins, upgrade levels, best run.

**Authoring in the Anvil** (no Anvil change needed): a `helper` character type with a sprite and N `helper` characters that stand nowhere until bought; M `thing` characters (already tagged `thing`) that stand nowhere until the game places them; a `buy` sound; the existing `pickup` and `game_over` sounds. The game places and removes characters only through `Play_State`. Tuning numbers (base run seconds, costs) can move into world parameters later.

**Game structure.**
- `game/shop.odin`: the upgrade table, cost and effect functions (pure, tested), buying.
- `game/helpers.odin`: a breadth-first path step toward the nearest Thing over non-solid cells (extends `reach.odin`), one step each time a helper's clock fires; helpers block each other (the runtime refuses an occupied cell) and wait.
- `game/save.odin`: the save model <-> JSON (`core:encoding/json`, spec JSON, integers only; reject bad values), with tests. The Tool's `take_save`/`saved`/`wants_load`/`load` hooks, file `save.json`. Saved after every purchase and at the end of each run; loaded once at start.
- The shop is a list driven by up/down/green (and the on-screen pad), red leaves for the next run; every screen is reachable with keyboard, gamepad and mouse.

**Saving.** The game sets `Tool.take_autosave` (Anvil story 13): native writes `go-get-the-thing-save.json` in the working directory, the web build stores it in browser storage only (no download) and restores it at start. Verified in the browser: buy, reload, the purchase is kept.

**Order of work.** (1) Author helper characters, extra Things and the `buy` sound in the Anvil. (2) Upgrade model, costs, save/load with tests. (3) Run/Shop state machine and shop screen. (4) Helpers. (5) Balance by playing, then web.

**Balance (simulated October 22, 2026).** `game/sim_test.odin` plays whole runs with a bot (`./build.sh test -define:SIM=true -define:SIM_FRAME=40 -define:ODIN_TEST_NAMES=game.test_balance_report`, a few minutes). The first prices let a good player max everything in about 24 minutes, far too fast: income multiplies (Things x value x speed x helpers x run length) while most prices stopped under 1,200 coins. After steeper prices (growth 160-350 percent) a bot that plays every run maxes everything in about 144 minutes (137 runs), and one that goes AFK after buying two helpers in about 214 minutes. Run 1 earns about 8 coins, the first helper arrives around run 19 (10 minutes), and income plateaus at about 12,000 coins a run once the speed upgrades are done, leaving Thing value and run length as the long grind. Prices live in `UPGRADES` in `game/shop.odin`; re-run the simulation after changing them. If a still longer game is wanted, prestige (reset for a permanent multiplier) is the next step.

## Prestige and secondary effects (added October 22, 2026)

**Prestige.** Pressing PRESTIGE in the shop (a second press confirms, within about 2.5 seconds) trades the era for **gems**: gems = the square root of (coins earned since the last prestige / 1000), rounded down. Coins, upgrade levels and the era's earnings reset; gems, perks, the best run and the prestige count stay. It does nothing until the era is worth a gem. The save is version 2 (`era_earned`, `gems`, `prestiges`, `perks`); version 1 saves still load.

**Perks (bought with gems).** The shop lists them after the upgrades. The first: **TIME BONUS CHANCE**, +5 percent per level (10 levels, 2 gems for the first, then 150 percent growth), the chance that a Thing, picked up by the player or a helper, adds 5 seconds to the clock. The "+5 SEC" shows on the HUD for a moment and a `bonus` sound plays. A run can have at most 10 time bonuses: helpers pick up Things about six times a second late in the game, so even a 5 percent chance of 5 seconds adds time faster than the clock runs down and a run would never end. The dice are not rolled at all without the perk. More secondary effects can be added next to `roll_secondary_effect` in `game/run.odin`.

**Simulated numbers** (bot plays every run, prestiges as soon as it is worth N gems, spends gems on the perk):
- No prestige: all upgrades maxed after about 132 minutes; income plateaus around 15,000 coins a run.
- Prestige at 5 gems (about 25,000 coins earned): eras of 41, 32, 26, 24 and 24 minutes.
- Prestige at 10 gems (about 100,000 coins earned): eras of 64, 39, 37, 35 and 35 minutes.
- The perk speeds the next era by about 40 percent by level 3 or 4 and then stops helping: with the 10-bonus cap, higher levels hardly change a late-game run. Perk levels beyond about 4 matter little until the cap grows or more effects exist. That is the main thing to tune next.

**Perk tuning (October 22, 2026).** The time-bonus cap was why perk levels past about 4 did nothing. Two changes: (1) the cap now grows with the perk: `time_bonus_cap` = 4 + 2 per TIME BONUS CHANCE level (6 at level 1, 24 at level 10; still finite, so a run always ends); (2) a second perk, **LUCKY COINS** (+4 percent per level, 10 levels, 3 gems then 150 percent growth): a picked-up Thing pays 5 times its coins by that chance (`roll_secondary_effect`; plays the `bonus` sound, no new HUD text; the dice are not rolled without the perk). The shop's rows are 10 pixels high now to fit the extra row. The simulation buys whichever perk is cheaper first.

Simulated again (same bot): prestige at 5 gems gives eras of 42, 29, 23, 22 and 22 minutes (was 41, 32, 26, 24, 24), perks ending at time-chance 3 and lucky 2; prestige at 10 gems gives 64, 37, 30, 25 and 24 minutes (was 64, 39, 37, 35, 35), perks ending at 4 and 3. Later eras now keep getting faster as perk levels rise instead of flattening at 35 minutes.

**Early game re-balance (October 22, 2026).** The playtest notes (code reading only) said run 1 buys nothing and the first helper takes about 10 minutes. THING VALUE now costs 8 (was 12), so run 1's 8 coins buy the first upgrade, and HELPERS cost 150 (was 250). With both perks in, a bot that plays every run: first helper in run 12 (was 19), first upgrade after run 1 (was run 2). Prestige at 5 gems: eras of 36, 24, 21, 18 and 20 minutes (was 42, 29, 23, 22, 22); at 10 gems: 56, 32, 29, 24 and 22 minutes. Late game is unchanged (the last levels cost the same up to rounding). Still open: the perk levels past about 4 and whether the plateau phase is too long need hands-on play.

**Playtest polish (October 22, 2026).** Helpers now take the Things in turn (`helper_target` in `game/helpers.odin`: each aims for the nearest Thing no earlier helper has taken), so they no longer crowd onto one; this cost the simulation a little (prestige at 5 gems: eras of 37, 26, 22, 19 and 21 minutes; at 10 gems: 58, 32, 31, 23 and 21). The shop says NEW BEST!, shows the era's progress toward the next gem (`ERA 340/1000` on the PRESTIGE row, `NEXT GEM AT n ERA COINS` once a gem is earned), says when there is nothing to buy yet, and no longer repeats coins and best in the HUD strip. The title lists the controls. Not done: a run-end result screen, banking a run's coins when the window closes mid-run, and a second gem sink.

**Automation unlocks (October 26, 2026; from `FINDINGS.md`).** Three one-time unlocks, each with an on/off switch (Green on the owned row; saved, version 3, `auto_off`). All in `game/auto.odin`, constants in `game/shop.odin`.
- **AUTO START** (coin upgrade, 1000, resets on prestige like the others): on the START RUN row a 15 second countdown shows on the row; moving off cancels it and coming back restarts it. With it on, the result screen also moves on by itself after 4 seconds (otherwise an idle player would stall there).
- **AUTO BUY** (gem perk, 3 gems): after 10 seconds without any input in the shop it buys a random affordable perk. With nothing affordable there is no timer.
- **AUTO PLAY** (gem perk, 5 gems): the player's sprite walks to the nearest Thing like a helper, at the player's own speed. Player input steers instead and the autopilot resumes after 1 second without input.
The prices are placeholders and the simulation ignores these unlocks. Not done: a visible AUTO BUY countdown.

**Coin boost perk (October 28, 2026).** A review said the first prestige felt pointless (2 gems bought one +5% time-chance level). New gem perk **COIN BOOST**: +25 percent coins from every Thing per level (`COIN_BOOST_PCT_PER_LEVEL`, 10 levels, 1 gem for the first then 140 percent growth: 1, 2, 3, 5, 8 ...), applied in `coins_per_thing` (lucky payouts, helpers and auto play too) and rounded up so it is felt while a Thing pays 1 coin. The shop rows are 8 pixels high now to fit the extra row. Simulated (same bot, perks bought cheapest first): prestige at 5 gems gives eras of 37, 21, 18, 12 and 11 minutes (was 37, 26, 22, 19, 21); at 10 gems 58, 27, 18, 17 and 11 (was 58, 32, 31, 23, 21). Era 2 is about 43 percent faster than era 1 (was about 30). Not simulated: prestiging at only 2 gems (the reviewer's case: one boost level, +25 percent); the late-game plateau is higher (last run 7,300 vs 4,074 after five eras) so the grind-length question in tasks 27 and 149 still needs hands-on play.
