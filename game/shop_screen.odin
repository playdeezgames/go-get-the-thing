// The shop between runs: a list (start a run, then the upgrades) driven by up, down and green.
package game

import cm "anvil:common"
import "core:fmt"

SHOP_ROWS :: 1 + len(Upgrade) // row 0 starts a run, then one row per upgrade
SHOP_TOP_Y :: 28
SHOP_ROW_H :: 14
SHOP_WHAT_Y :: 134
SHOP_MESSAGE_Y :: 146
SHOP_LEVEL_X :: 150
SHOP_MESSAGE_MS :: 1500.0

shop_command :: proc(g: ^Game, action: cm.Action) {
	#partial switch action {
	case .Up:
		g.shop_sel = (g.shop_sel + SHOP_ROWS - 1) % SHOP_ROWS
	case .Down:
		g.shop_sel = (g.shop_sel + 1) % SHOP_ROWS
	case .Green:
		if g.shop_sel == 0 {
			start_run(g)
			return
		}
		switch buy(&g.progress, Upgrade(g.shop_sel - 1)) {
		case .Bought:
			play(g, g.buy_pcm)
			request_save(g)
			say(g, "BOUGHT")
		case .Too_Poor:
			say(g, "NOT ENOUGH COINS")
		case .Max_Level:
			say(g, "ALREADY AT THE MAXIMUM")
		}
	}
}

say :: proc(g: ^Game, text: string) {
	g.message = text
	g.message_ms = SHOP_MESSAGE_MS
}

// The three columns of a shop row: its name, the level and the price (on the temp allocator). Row 0
// has only a name.
shop_row_text :: proc(g: ^Game, row: int) -> (name, level, cost: string) {
	if row == 0 {
		return "START RUN", "", ""
	}
	u := Upgrade(row - 1)
	have := g.progress.levels[u]
	cost = have >= UPGRADES[u].max_level ? "MAX" : fmt.tprintf("%d", next_cost(g.progress, u))
	return UPGRADES[u].name, fmt.tprintf("LV %d/%d", have, UPGRADES[u].max_level), cost
}

draw_shop :: proc(g: ^Game, r: ^cm.Renderer) {
	white, grey, gold := cm.Color{255, 255, 255}, cm.Color{110, 110, 110}, cm.Color{255, 221, 85}
	cm.draw_text(r, 8, 4, "SHOP", gold)
	coins := fmt.tprintf("COINS %d", g.progress.coins)
	cm.draw_text(r, cm.SCREEN_W - 8 - cm.text_width(coins), 4, coins, white)
	cm.draw_text(r, 8, 14, fmt.tprintf("LAST RUN +%d   BEST %d", g.last_run, g.progress.best_run), grey)
	for row in 0 ..< SHOP_ROWS {
		y := SHOP_TOP_Y + row * SHOP_ROW_H
		selected := row == g.shop_sel
		if selected {
			cm.renderer_fill_rect(r, 0, y - 3, cm.SCREEN_W, SHOP_ROW_H - 1, cm.Color{0, 0, 90})
			cm.draw_text(r, 4, y, ">", gold)
		}
		name, level, cost := shop_row_text(g, row)
		ink := white
		if row > 0 {
			u := Upgrade(row - 1)
			if g.progress.levels[u] >= UPGRADES[u].max_level || g.progress.coins < next_cost(g.progress, u) {
				ink = grey // maxed, or cannot afford it yet
			}
		}
		cm.draw_text(r, 14, y, name, row == 0 ? gold : ink)
		cm.draw_text(r, SHOP_LEVEL_X, y, level, ink)
		cm.draw_text(r, cm.SCREEN_W - 8 - cm.text_width(cost), y, cost, ink)
	}
	what := "START THE NEXT RUN"
	if g.shop_sel > 0 {
		what = UPGRADES[Upgrade(g.shop_sel - 1)].what
	}
	cm.draw_text(r, 14, SHOP_WHAT_Y, what, cm.Color{150, 190, 255})
	if g.message_ms > 0 {
		cm.draw_text(r, 14, SHOP_MESSAGE_Y, g.message, gold)
	}
}
