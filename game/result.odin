// The result screen: what the run that just ended earned, shown before the shop.
package game

import cm "anvil:common"
import "core:fmt"

RESULT_LOCK_MS :: 700.0 // input is ignored this long, so a key still being mashed does not skip it

// Green or Red moves on to the shop (the directions do nothing here).
result_command :: proc(g: ^Game, action: cm.Action) {
	if g.result_ms < RESULT_LOCK_MS || (action != .Green && action != .Red) {
		return
	}
	g.state = .Shop
	g.shop_sel = 0
}

draw_result :: proc(g: ^Game, r: ^cm.Renderer) {
	white, grey, gold := cm.Color{255, 255, 255}, cm.Color{110, 110, 110}, cm.Color{255, 221, 85}
	all := cm.Rect{0, 0, cm.SCREEN_W, 0}
	centred(r, all, 14, "TIME UP!", gold)
	centred(r, all, 34, fmt.tprintf("YOU      %d %s   +%d", g.run_things[0], things_word(g.run_things[0]), g.run_coins[0]), white)
	if g.progress.levels[.Helpers] > 0 || g.run_things[1] > 0 {
		centred(r, all, 48, fmt.tprintf("HELPERS  %d %s   +%d", g.run_things[1], things_word(g.run_things[1]), g.run_coins[1]), white)
	}
	centred(r, all, 68, fmt.tprintf("THIS RUN +%d", g.last_run), gold)
	if g.new_best {
		centred(r, all, 84, "NEW BEST!", cm.Color{85, 255, 85})
	} else {
		centred(r, all, 84, fmt.tprintf("BEST %d", g.progress.best_run), grey)
	}
	if g.new_room {
		centred(r, all, 94, "NEW ROOM OPENED!", cm.Color{85, 255, 85})
	}
	centred(r, all, 108, fmt.tprintf("COINS %d", g.progress.coins), white)
	if g.result_ms >= RESULT_LOCK_MS {
		centred(r, all, 136, fmt.tprintf("%s TO CONTINUE", cm.action_label(g.input_map, .Green)), white)
	}
}

things_word :: proc(n: int) -> string {
	return n == 1 ? "THING" : "THINGS"
}
