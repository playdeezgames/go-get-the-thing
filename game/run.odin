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
	g.has_queued = false
	g.time_bonuses = 0
	g.bonus_flash_ms = 0
	g.state = .Playing
	for i in 1 ..< min(thing_count(g.progress), g.thing_n) {
		place_on_free_cell(g, g.things[i])
	}
	start_helpers(g)
}

// The clock ran out: bank the coins, remember the best run, save, and go to the shop.
finish_run :: proc(g: ^Game) {
	g.progress.coins = min(g.progress.coins + g.score, MAX_SAVED_NUMBER)
	g.progress.era_earned = min(g.progress.era_earned + g.score, MAX_SAVED_NUMBER)
	g.progress.best_run = max(g.progress.best_run, g.score)
	g.last_run = g.score
	g.has_queued = false
	g.holding = false // a pad direction still held would race through the shop rows
	request_save(g)
	g.shop_sel = 0
	g.message_ms = 0
	g.state = .Shop
	play(g, g.over_pcm)
}

// The command the frontends send. The title goes to the shop, the shop is a list, and in a run the
// four directions move the player (no faster than the player-speed upgrade allows; a press during the
// cooldown is kept and made when it ends).
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
			g.queued, g.has_queued = action, true // the latest press wins; it fires when the cooldown ends
			return
		}
		if move_player(g, dx, dy) == .Moved {
			g.step_cooldown_ms = player_step_ms(g.progress)
		}
	}
}

// One step for the player (nothing moves unless a run is being played); see `step_collecting`.
move_player :: proc(g: ^Game, dx, dy: int) -> rt.Move_Result {
	if g.state != .Playing {
		return .Not_Placed
	}
	return step_collecting(g, g.player, dx, dy, CHANNEL_EFFECTS)
}

// One step for a character (the player or a helper). Walking onto a Thing is a pickup: it pays, the
// Thing leaves its cell (the runtime would call it Occupied), the character steps in and the Thing
// reappears elsewhere. Returns what happened.
step_collecting :: proc(g: ^Game, ci, dx, dy, sound_channel: int) -> rt.Move_Result {
	result, tx, ty := rt.play_can_step(&g.play, g.world, ci, dx, dy)
	if result == .Occupied {
		if who := rt.play_character_at(&g.play, g.map_index, tx, ty); who >= 0 && rt.character_has_tag(g.world, who, g.thing_tag) {
			g.score += coins_per_thing(g.progress, g.points_per_thing)
			play(g, g.pickup_pcm, sound_channel)
			roll_secondary_effect(g)
			rt.play_unplace(&g.play, who)
			result = rt.play_step(&g.play, g.world, ci, dx, dy)
			place_on_free_cell(g, who)
			return result
		}
	}
	return rt.play_step(&g.play, g.world, ci, dx, dy)
}

// Puts a character (a Thing, a helper) on a random free spawn cell: a `spawn` cell the player can
// walk to (so not solid, not walled off, not the player's own, not holding another character). Returns
// false (leaving it off the map) if there is none.
place_on_free_cell :: proc(g: ^Game, thing: int) -> bool {
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

// A picked-up Thing may carry secondary effects, by chance (perks bought with gems): extra time on
// the clock (at most `time_bonus_cap` times a run) and a lucky payout of LUCKY_MULTIPLIER times the
// coins. The dice are not rolled at all without the perk, so a game without perks draws the same
// numbers as before.
roll_secondary_effect :: proc(g: ^Game) {
	if chance := time_chance_pct(g.progress); chance > 0 && g.time_bonuses < time_bonus_cap(g.progress) && random_below(g, 100) < chance {
		g.ms_left += TIME_BONUS_MS
		g.time_bonuses += 1
		g.bonus_flash_ms = BONUS_FLASH_MS
		play(g, g.bonus_pcm, CHANNEL_BONUS)
	}
	if chance := lucky_chance_pct(g.progress); chance > 0 && random_below(g, 100) < chance {
		g.score += coins_per_thing(g.progress, g.points_per_thing) * (LUCKY_MULTIPLIER - 1)
		play(g, g.bonus_pcm, CHANNEL_BONUS)
	}
}
