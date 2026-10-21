// Go Get the Thing!: the game itself. Platform-independent: no frontend code, only the Anvil's runtime
// and renderer interface. `app/` wraps it in the Tool the Anvil's frontends drive.
package game

import rt "anvil:anvil_runtime"
import cm "anvil:common"
import "core:fmt"

WORLD_FILE :: #load("../world.json")
TAGS_FILE :: #load("../game_tags.json")

MAP_NAME :: "arena"

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
	rt.play_init(&g.play, g.world)
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
}
