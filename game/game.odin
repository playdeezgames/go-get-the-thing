// Go Get the Thing!: the game itself. Platform-independent: no frontend code, only the Anvil's runtime
// and renderer interface. `app/` wraps it in the Tool the Anvil's frontends drive.
package game

import rt "anvil:anvil_runtime"
import cm "anvil:common"
import "core:fmt"

WORLD_FILE :: #load("../world.json")
TAGS_FILE :: #load("../game_tags.json")

MAP_NAME :: "arena"

DEFAULT_ROUND_SECONDS :: 30
DEFAULT_POINTS_PER_THING :: 1

SOUND_PICKUP :: "pickup"
SOUND_GAME_OVER :: "game_over"
SOUND_BUY :: "buy"
MAX_THINGS :: 4
MAX_HELPERS :: 4
CHANNEL_EFFECTS :: 0 // a new effect replaces the one still playing
CHANNEL_HELPERS :: 1 // helpers pick up on their own channel, so they do not cut off the player's sound

// Title -> Shop -> Playing (a run) -> Shop -> Playing ...
State :: enum {
	Title,
	Shop,
	Playing,
}

Game :: struct {
	world:      ^rt.World, // ~21 MB: on the heap, never by value
	tags:       rt.Game_Tags,
	play:       rt.Play_State, // where every character is now; the world itself is never changed
	map_index:  int,
	player:     int, // character indexes
	thing:      int, // the first Thing (things[0])
	things:     [MAX_THINGS]int, // every character tagged `thing`, in world order
	thing_n:    int,
	helpers:    [MAX_HELPERS]int, // every character of the type `helper`, in world order
	helper_n:   int,
	helper_clock: [MAX_HELPERS]f64, // until each helper steps again
	thing_tag:  int,
	spawn_tag:  int,
	error:      string, // set when start-up failed: shown instead of the game
	state:      State,
	score:      int, // the coins earned in this run (banked into progress.coins when it ends)
	last_run:   int, // the coins the last run earned, shown in the shop
	ms_left:    f64,
	round_ms:   f64,
	points_per_thing: int,
	rng:        u64, // xorshift state: seedable, and the same on native and wasm
	input_map:  ^cm.Input_Map, // for on-screen command names; nil gives the defaults
	pickup_pcm: []i16, // the sounds, rendered once at start-up (heap), so requests can point at them
	over_pcm:   []i16,
	buy_pcm:    []i16,
	audio:      [8]cm.Audio_Request, // queued for the frontend, oldest first
	audio_n:    int,
	holding:    bool, // a pad button is held with the mouse
	held:       cm.Action,
	repeat_ms:  f64, // until the held direction repeats
	progress:   Progress, // kept between runs (see save.odin)
	load_requested: bool, // the save is asked for once, at start
	save_requested: bool,
	step_cooldown_ms: f64, // until the player may step again (the player-speed upgrade)
	shop_sel:   int, // the highlighted shop row: 0 = start a run, then the upgrades
	message:    string, // a short note in the shop (static text), shown until message_ms runs out
	message_ms: f64,
}

// Loads the embedded world and checks it has what the game needs. On failure `error` says why.
init :: proc(g: ^Game) {
	g^ = {}
	g.load_requested = true
	g.world = rt.new_world()
	if err := rt.load(g.world, WORLD_FILE); err != "" {
		g.error = fmt.aprintf("WORLD: %s", err)
		return
	}
	if err := rt.parse_game_tags(TAGS_FILE, &g.tags); err != "" {
		g.error = fmt.aprintf("TAGS: %s", err)
		return
	}
	if missing := rt.required_missing(g.world, &g.tags); len(missing) > 0 {
		g.error = fmt.aprintf("WORLD LACKS TAG %s", missing[0])
		return
	}
	if missing := rt.missing_sounds(g.world, {SOUND_PICKUP, SOUND_GAME_OVER, SOUND_BUY}); len(missing) > 0 {
		g.error = fmt.aprintf("WORLD LACKS SOUND %s", missing[0])
		return
	}
	pickup, _ := rt.find_sound(g.world, SOUND_PICKUP)
	over, _ := rt.find_sound(g.world, SOUND_GAME_OVER)
	rendered: bool
	if g.pickup_pcm, rendered = rt.sound_pcm(g.world, pickup, context.allocator); !rendered {
		g.error = "SOUND pickup HAS NO NOTES"
		return
	}
	if g.over_pcm, rendered = rt.sound_pcm(g.world, over, context.allocator); !rendered {
		g.error = "SOUND game_over HAS NO NOTES"
		return
	}
	buy, _ := rt.find_sound(g.world, SOUND_BUY)
	if g.buy_pcm, rendered = rt.sound_pcm(g.world, buy, context.allocator); !rendered {
		g.error = "SOUND buy HAS NO NOTES"
		return
	}
	ok: bool
	g.thing_tag, _ = rt.find_tag(g.world, "thing")
	g.spawn_tag, _ = rt.find_tag(g.world, "spawn")
	if g.map_index, ok = rt.find_map(g.world, MAP_NAME); !ok {
		g.error = fmt.aprintf("WORLD HAS NO MAP %s", MAP_NAME)
		return
	}
	if g.player, ok = rt.player(g.world); !ok {
		g.error = "WORLD HAS NO PLAYER"
		return
	}
	for ci in 0 ..< rt.character_count(g.world) {
		if rt.character_has_tag(g.world, ci, g.thing_tag) && g.thing_n < MAX_THINGS {
			g.things[g.thing_n] = ci
			g.thing_n += 1
		}
	}
	if g.thing_n == 0 {
		g.error = "WORLD HAS NO THING"
		return
	}
	g.thing = g.things[0]
	for ci in 0 ..< rt.character_count(g.world) {
		if ct := rt.character_type(g.world, ci); ct != nil && cm.name_str(&ct.name) == "helper" && g.helper_n < MAX_HELPERS {
			g.helpers[g.helper_n] = ci
			g.helper_n += 1
		}
	}
	if need := UPGRADES[.Helpers].max_level; g.helper_n < need {
		g.error = fmt.aprintf("WORLD NEEDS %d HELPERS", need)
		return
	}
	if need := 1 + UPGRADES[.More_Things].max_level; g.thing_n < need {
		g.error = fmt.aprintf("WORLD NEEDS %d THINGS", need)
		return
	}
	g.round_ms = f64(max(rt.param_number(g.world, "round_seconds", DEFAULT_ROUND_SECONDS), 1)) * 1000
	g.points_per_thing = rt.param_number(g.world, "points_per_thing", DEFAULT_POINTS_PER_THING)
	g.ms_left = g.round_ms
	set_seed(g, 1)
	rt.play_init(&g.play, g.world)
	reach, width := player_reach(g)
	if tp := rt.play_position(&g.play, g.thing); !tp.placed || !reach[tp.y * width + tp.x] {
		g.error = "THE THING CANNOT BE REACHED"
	}
}

set_seed :: proc(g: ^Game, seed: u64) {
	g.rng = seed != 0 ? seed : 1 // xorshift must not be 0
}

// A number in 0..<n.
random_below :: proc(g: ^Game, n: int) -> int {
	g.rng ~= g.rng << 13
	g.rng ~= g.rng >> 7
	g.rng ~= g.rng << 17
	return int(g.rng % u64(n))
}

// Queues a sound effect for the frontend (dropped if the queue is full).
play :: proc(g: ^Game, samples: []i16, channel := CHANNEL_EFFECTS) {
	if g.audio_n < len(g.audio) {
		g.audio[g.audio_n] = {action = .Play, channel = channel, samples = samples, rate = cm.SOUND_RATE}
		g.audio_n += 1
	}
}

// The next queued audio request, oldest first: the Tool's `take_audio`.
take_audio :: proc(g: ^Game) -> (req: cm.Audio_Request, ok: bool) {
	if g.audio_n == 0 {
		return {}, false
	}
	req = g.audio[0]
	copy(g.audio[:], g.audio[1:g.audio_n])
	g.audio_n -= 1
	return req, true
}

// --- saving: the Tool's file hooks (the frontends do the file IO) ----------------------------------

// True once, at start: the frontend then reads the save file, if there is one, and calls `load_save`.
wants_load :: proc(g: ^Game) -> bool {
	asked := g.load_requested
	g.load_requested = false
	return asked
}

// A save file's bytes. A bad file is refused and changes nothing.
load_save :: proc(g: ^Game, bytes: []u8) -> bool {
	p, ok := progress_from_json(bytes)
	if ok {
		g.progress = p
	}
	return ok
}

request_save :: proc(g: ^Game) {
	g.save_requested = true
}

// The save text if one was asked for since the last call (on the temp allocator).
take_save :: proc(g: ^Game) -> (text: string, ok: bool) {
	if !g.save_requested {
		return "", false
	}
	g.save_requested = false
	return progress_to_json(g.progress), true
}

// Called every frame with the elapsed milliseconds (the frontends clamp it).
update :: proc(g: ^Game, dt_ms: f64) {
	if !(dt_ms > 0) {
		return
	}
	g.message_ms = max(g.message_ms - dt_ms, 0)
	g.step_cooldown_ms = max(g.step_cooldown_ms - dt_ms, 0) // before the repeat, which may step
	repeat_held(g, dt_ms)
	if g.state != .Playing {
		return
	}
	run_helpers(g, dt_ms)
	g.ms_left -= dt_ms
	if g.ms_left <= 0 {
		g.ms_left = 0
		finish_run(g)
	}
}

destroy :: proc(g: ^Game) {
	delete(g.pickup_pcm)
	delete(g.over_pcm)
	delete(g.buy_pcm)
	free(g.world)
	g^ = {}
}

// Draws a whole frame and presents it (the SDL2 frontend leaves presenting to the tool).
draw :: proc(g: ^Game, r: ^cm.Renderer) {
	draw_frame(g, r)
	cm.renderer_present(r)
}

draw_frame :: proc(g: ^Game, r: ^cm.Renderer) {
	cm.renderer_clear(r, cm.Color{0, 0, 0})
	if g.error != "" {
		cm.draw_text(r, 8, 8, "CANNOT START", cm.Color{255, 85, 85})
		cm.draw_text(r, 8, 20, g.error, cm.Color{255, 255, 255})
		return
	}
	white := cm.Color{255, 255, 255}
	if g.state == .Shop {
		draw_shop(g, r)
	} else {
		cols, rows, _ := rt.map_size(g.world, g.map_index)
		window := rt.zoom_window(g.world, g.map_index, 0, 0, cols, rows, 0, 0, 1)
		rt.draw_terrain(r, g.world, window)
		rt.draw_characters(r, g.world, &g.play, window)
		if g.state == .Title {
			banner(r, 56, "GO GET THE THING!", white)
			banner(r, 72, fmt.tprintf("%s TO START", cm.action_label(g.input_map, .Green)), white)
		}
	}
	draw_pad(g, r)
	draw_hud(g, r)
}

// Whole seconds left, rounded up so the clock shows 0 only when the round is over.
seconds_left :: proc(g: ^Game) -> int {
	return int((g.ms_left + 999) / 1000)
}

// Text centred on the surface at row y, on a black strip so it reads over the room.
banner :: proc(r: ^cm.Renderer, y: int, text: string, c: cm.Color) {
	w := cm.text_width(text)
	x := (cm.SCREEN_W - w) / 2
	cm.renderer_fill_rect(r, x - 3, y - 2, w + 6, cm.GLYPH_H + 4, cm.Color{0, 0, 0})
	cm.draw_text(r, x, y, text, c)
}
