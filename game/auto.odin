// The automation unlocks: AUTO START (the shop starts the run), AUTO BUY (the shop buys a perk when
// left idle) and AUTO PLAY (the player's sprite collects like a helper). Each has a switch, see `Toggle`.
package game

// Shop timers, run from `update`. Outside the shop both stand at 0.
run_shop_automation :: proc(g: ^Game, dt_ms: f64) {
	if g.state != .Shop {
		g.idle_ms, g.auto_start_ms = 0, 0
		return
	}
	if toggle_on(g.progress, .Auto_Start) && g.shop_sel == 0 {
		g.auto_start_ms += dt_ms // moving off the row cancels it; coming back starts over
		if g.auto_start_ms >= AUTO_START_MS {
			g.auto_start_ms = 0
			start_run(g)
			return
		}
	} else {
		g.auto_start_ms = 0
	}
	candidates: [len(Perk)]Perk
	n := 0
	if toggle_on(g.progress, .Auto_Buy) {
		for k in Perk {
			if perk_affordable(g.progress, k) {
				candidates[n] = k
				n += 1
			}
		}
	}
	if n == 0 {
		g.idle_ms = 0 // nothing to buy, so no timer
		return
	}
	g.idle_ms += dt_ms
	if g.idle_ms >= AUTO_BUY_IDLE_MS {
		g.idle_ms = 0
		k := candidates[random_below(g, n)]
		if buy_perk(&g.progress, k) == .Bought {
			play(g, g.buy_pcm)
			request_save(g)
			sayf(g, "AUTO BOUGHT %s", PERKS[k].name)
		}
	}
}

// One step of the player towards the nearest Thing, when AUTO PLAY is on and the player has not
// touched the controls for a moment. Steps no faster than the player's own speed.
auto_play_step :: proc(g: ^Game) {
	if !toggle_on(g.progress, .Auto_Play) || g.auto_play_pause_ms > 0 || g.step_cooldown_ms > 0 || g.has_queued {
		return
	}
	if dx, dy, ok := step_towards_nearest_thing(g, g.player); ok && move_player(g, dx, dy) == .Moved {
		g.step_cooldown_ms = player_step_ms(g.progress)
	}
}
