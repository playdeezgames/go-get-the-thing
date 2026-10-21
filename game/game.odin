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

State :: enum {
	Title,
	Playing,
	Game_Over,
}

Game :: struct {
	world:      ^rt.World, // ~21 MB: on the heap, never by value
	tags:       rt.Game_Tags,
	play:       rt.Play_State, // where every character is now; the world itself is never changed
	map_index:  int,
	player:     int, // character indexes
	thing:      int,
	thing_tag:  int,
	spawn_tag:  int,
	error:      string, // set when start-up failed: shown instead of the game
	state:      State,
	score:      int,
	ms_left:    f64,
	round_ms:   f64,
	points_per_thing: int,
	rng:        u64, // xorshift state: seedable, and the same on native and wasm
	input_map:  ^cm.Input_Map, // for on-screen command names; nil gives the defaults
}

// Loads the embedded world and checks it has what the game needs. On failure `error` says why.
init :: proc(g: ^Game) {
	g^ = {}
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
	g.thing = -1
	for ci in 0 ..< rt.character_count(g.world) {
		if rt.character_has_tag(g.world, ci, g.thing_tag) {
			g.thing = ci
			break
		}
	}
	if g.thing < 0 {
		g.error = "WORLD HAS NO THING"
		return
	}
	g.round_ms = f64(max(rt.param_number(g.world, "round_seconds", DEFAULT_ROUND_SECONDS), 1)) * 1000
	g.points_per_thing = rt.param_number(g.world, "points_per_thing", DEFAULT_POINTS_PER_THING)
	g.ms_left = g.round_ms
	set_seed(g, 1)
	rt.play_init(&g.play, g.world)
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

// A new round: everyone back where the world put them, no score, a full clock.
start_round :: proc(g: ^Game) {
	rt.play_init(&g.play, g.world)
	g.score = 0
	g.ms_left = g.round_ms
	g.state = .Playing
}

// The command the frontends send. On the title and game-over screens green starts a round; while
// playing the four directions move the player.
handle_command :: proc(g: ^Game, action: cm.Action) {
	if g.error != "" {
		return
	}
	switch g.state {
	case .Title, .Game_Over:
		if action == .Green {
			start_round(g)
		}
	case .Playing:
		switch action {
		case .Up:
			move_player(g, 0, -1)
		case .Down:
			move_player(g, 0, 1)
		case .Left:
			move_player(g, -1, 0)
		case .Right:
			move_player(g, 1, 0)
		case .Green, .Red, .Blue, .Yellow:
		}
	}
}

// One step for the player. Walking onto the Thing is a pickup: it scores, the Thing leaves its cell
// (the runtime would call it Occupied), the player steps in and the Thing reappears elsewhere.
// Returns what happened; nothing moves unless the round is being played.
move_player :: proc(g: ^Game, dx, dy: int) -> rt.Move_Result {
	if g.state != .Playing {
		return .Not_Placed
	}
	result, tx, ty := rt.play_can_step(&g.play, g.world, g.player, dx, dy)
	if result == .Occupied && rt.play_character_at(&g.play, g.map_index, tx, ty) == g.thing {
		g.score += g.points_per_thing
		rt.play_unplace(&g.play, g.thing)
		result = rt.play_step(&g.play, g.world, g.player, dx, dy)
		respawn_thing(g)
		return result
	}
	return rt.play_step(&g.play, g.world, g.player, dx, dy)
}

// Puts the Thing on a random free spawn cell: a `spawn` cell that is not solid and not the
// player's. Returns false (leaving it off the map) if there is none.
respawn_thing :: proc(g: ^Game) -> bool {
	spawn := rt.cells_with_tag(g.world, g.map_index, g.spawn_tag)
	free_cells := make([dynamic][2]int, 0, len(spawn), context.temp_allocator)
	pp := rt.play_position(&g.play, g.player)
	for c in spawn {
		if rt.cell_is_solid(g.world, g.map_index, c.x, c.y) || (c.x == pp.x && c.y == pp.y) {
			continue
		}
		if rt.play_character_at(&g.play, g.map_index, c.x, c.y) >= 0 {
			continue
		}
		append(&free_cells, c)
	}
	if len(free_cells) == 0 {
		return false
	}
	c := free_cells[random_below(g, len(free_cells))]
	return rt.play_place(&g.play, g.world, g.thing, g.map_index, c.x, c.y) == .Placed
}

// Called every frame with the elapsed milliseconds (the frontends clamp it).
update :: proc(g: ^Game, dt_ms: f64) {
	if g.state != .Playing || !(dt_ms > 0) {
		return
	}
	g.ms_left -= dt_ms
	if g.ms_left <= 0 {
		g.ms_left = 0
		g.state = .Game_Over
	}
}

destroy :: proc(g: ^Game) {
	free(g.world)
	g^ = {}
}

draw :: proc(g: ^Game, r: ^cm.Renderer) {
	cm.renderer_clear(r, cm.Color{0, 0, 0})
	if g.error != "" {
		cm.draw_text(r, 8, 8, "CANNOT START", cm.Color{255, 85, 85})
		cm.draw_text(r, 8, 20, g.error, cm.Color{255, 255, 255})
		return
	}
	cols, rows, _ := rt.map_size(g.world, g.map_index)
	window := rt.zoom_window(g.world, g.map_index, 0, 0, cols, rows, 0, 0, 1)
	rt.draw_terrain(r, g.world, window)
	rt.draw_characters(r, g.world, &g.play, window)
	white := cm.Color{255, 255, 255}
	switch g.state {
	case .Title:
		banner(r, 60, "GO GET THE THING!", white)
		banner(r, 76, fmt.tprintf("%s TO START", cm.action_label(g.input_map, .Green)), white)
	case .Playing:
		cm.draw_text(r, 8, 5, fmt.tprintf("SCORE %d", g.score), white)
		time_text := fmt.tprintf("TIME %d", seconds_left(g))
		cm.draw_text(r, cm.SCREEN_W - 8 - cm.text_width(time_text), 5, time_text, white)
	case .Game_Over:
		banner(r, 56, "TIME UP", white)
		banner(r, 68, fmt.tprintf("FINAL SCORE %d", g.score), white)
		banner(r, 84, fmt.tprintf("%s TO PLAY AGAIN", cm.action_label(g.input_map, .Green)), white)
	}
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
