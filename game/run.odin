// A run: the timed round in the room. Walk onto Things for coins; helpers and upgrades come from the
// shop between runs.
package game

import rt "anvil:anvil_runtime"
import cm "anvil:common"

// A new run: everyone back where the world put them, no coins earned, the clock full (the run-length
// upgrade lengthens it) and as many Things in the room as the upgrades allow.
start_run :: proc(g: ^Game) {
	rt.play_init(&g.play, g.world)
	g.score = 0
	g.ms_left = run_ms(g.progress, g.round_ms)
	g.step_cooldown_ms = 0
	g.state = .Playing
	for i in 1 ..< min(thing_count(g.progress), g.thing_n) {
		respawn_thing(g, g.things[i])
	}
}

// The clock ran out: bank the coins, remember the best run, save, and go to the shop.
finish_run :: proc(g: ^Game) {
	g.progress.coins = min(g.progress.coins + g.score, MAX_SAVED_NUMBER)
	g.progress.best_run = max(g.progress.best_run, g.score)
	g.last_run = g.score
	request_save(g)
	g.shop_sel = 0
	g.message_ms = 0
	g.state = .Shop
	play(g, g.over_pcm)
}

// The command the frontends send. The title goes to the shop, the shop is a list, and in a run the
// four directions move the player (no faster than the player-speed upgrade allows).
handle_command :: proc(g: ^Game, action: cm.Action) {
	if g.error != "" {
		return
	}
	switch g.state {
	case .Title:
		if action == .Green {
			g.state = .Shop
			g.shop_sel = 0
		}
	case .Shop:
		shop_command(g, action)
	case .Playing:
		dx, dy: int
		#partial switch action {
		case .Up:
			dy = -1
		case .Down:
			dy = 1
		case .Left:
			dx = -1
		case .Right:
			dx = 1
		case:
			return
		}
		if g.step_cooldown_ms > 0 {
			return
		}
		if move_player(g, dx, dy) == .Moved {
			g.step_cooldown_ms = player_step_ms(g.progress)
		}
	}
}

// One step for the player. Walking onto a Thing is a pickup: it pays, the Thing leaves its cell (the
// runtime would call it Occupied), the player steps in and the Thing reappears elsewhere. Returns
// what happened; nothing moves unless a run is being played.
move_player :: proc(g: ^Game, dx, dy: int) -> rt.Move_Result {
	if g.state != .Playing {
		return .Not_Placed
	}
	result, tx, ty := rt.play_can_step(&g.play, g.world, g.player, dx, dy)
	if result == .Occupied {
		if who := rt.play_character_at(&g.play, g.map_index, tx, ty); who >= 0 && rt.character_has_tag(g.world, who, g.thing_tag) {
			g.score += coins_per_thing(g.progress, g.points_per_thing)
			play(g, g.pickup_pcm)
			rt.play_unplace(&g.play, who)
			result = rt.play_step(&g.play, g.world, g.player, dx, dy)
			respawn_thing(g, who)
			return result
		}
	}
	return rt.play_step(&g.play, g.world, g.player, dx, dy)
}

// Puts a Thing on a random free spawn cell: a `spawn` cell the player can walk to (so not solid, not
// walled off, not the player's own, not holding another character). Returns false (leaving it off the
// map) if there is none.
respawn_thing :: proc(g: ^Game, thing: int) -> bool {
	spawn := rt.cells_with_tag(g.world, g.map_index, g.spawn_tag)
	free_cells := make([dynamic][2]int, 0, len(spawn), context.temp_allocator)
	pp := rt.play_position(&g.play, g.player)
	reach, width := player_reach(g)
	for c in spawn {
		if !reach[c.y * width + c.x] || (c.x == pp.x && c.y == pp.y) {
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
	return rt.play_place(&g.play, g.world, thing, g.map_index, c.x, c.y) == .Placed
}
