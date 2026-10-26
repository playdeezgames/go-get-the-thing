// The shop between runs: a list (start a run, the upgrades, the perks, prestige) driven by up, down
// and green.
package game

import cm "anvil:common"
import "core:fmt"

Row_Kind :: enum {
	Start,
	Upgrade,
	Perk,
	Prestige,
}

// Row 0 starts a run, then one row per upgrade, one per perk, and last PRESTIGE.
SHOP_ROWS :: 1 + len(Upgrade) + len(Perk) + 1
SHOP_TOP_Y :: 24
SHOP_ROW_H :: 9
SHOP_WHAT_Y :: 143
SHOP_MESSAGE_Y :: 152
SHOP_LEVEL_X :: 150
SHOP_MESSAGE_MS :: 2500.0

// What a row is: its kind and which upgrade or perk it holds.
row_kind :: proc(row: int) -> (kind: Row_Kind, index: int) {
	switch {
	case row == 0:
		return .Start, 0
	case row <= len(Upgrade):
		return .Upgrade, row - 1
	case row <= len(Upgrade) + len(Perk):
		return .Perk, row - 1 - len(Upgrade)
	}
	return .Prestige, 0
}

shop_command :: proc(g: ^Game, action: cm.Action) {
	armed := g.prestige_armed
	g.prestige_armed = false // anything but a second green on the PRESTIGE row disarms it
	#partial switch action {
	case .Red:
		start_run(g) // from any row
	case .Up:
		g.shop_sel = (g.shop_sel + SHOP_ROWS - 1) % SHOP_ROWS
	case .Down:
		g.shop_sel = (g.shop_sel + 1) % SHOP_ROWS
	case .Green:
		kind, index := row_kind(g.shop_sel)
		switch kind {
		case .Start:
			start_run(g)
		case .Upgrade:
			if t, is_toggle := upgrade_toggle(Upgrade(index)); is_toggle && toggle_unlocked(g.progress, t) {
				flip_toggle(g, t)
			} else {
				buy_result(g, buy(&g.progress, Upgrade(index)), "NOT ENOUGH COINS")
			}
		case .Perk:
			if t, is_toggle := perk_toggle(Perk(index)); is_toggle && toggle_unlocked(g.progress, t) {
				flip_toggle(g, t)
			} else {
				buy_result(g, buy_perk(&g.progress, Perk(index)), "NOT ENOUGH GEMS")
			}
		case .Prestige:
			prestige_pressed(g, armed)
		}
	}
}

// Green on an automation the player owns switches it on or off.
flip_toggle :: proc(g: ^Game, t: Toggle) {
	g.progress.auto_off[t] = !g.progress.auto_off[t]
	request_save(g)
	say(g, g.progress.auto_off[t] ? "SWITCHED OFF" : "SWITCHED ON")
}

buy_result :: proc(g: ^Game, result: Buy_Result, poor_message: string) {
	switch result {
	case .Bought:
		play(g, g.buy_pcm)
		request_save(g)
		say(g, "BOUGHT")
	case .Too_Poor:
		say(g, poor_message)
	case .Max_Level:
		say(g, "ALREADY AT THE MAXIMUM")
	}
}

// The first press of PRESTIGE only asks; the second one (before the note runs out) does it.
prestige_pressed :: proc(g: ^Game, armed: bool) {
	gain := gems_for_prestige(g.progress.era_earned)
	if gain == 0 {
		say(g, "EARN MORE COINS FIRST")
		return
	}
	if !armed {
		g.prestige_armed = true
		sayf(g, "PRESS AGAIN: +%d GEMS, COINS AND UPGRADES RESET", gain)
		return
	}
	gained := prestige(&g.progress)
	g.last_run = 0
	g.new_best = false
	play(g, g.prestige_pcm)
	request_save(g)
	sayf(g, "PRESTIGED: +%d GEMS", gained)
}

// A note in the shop (copied, so it may be built on the temp allocator).
say :: proc(g: ^Game, text: string) {
	n := copy(g.message_buf[:], text)
	g.message = string(g.message_buf[:n])
	g.message_ms = SHOP_MESSAGE_MS
}

sayf :: proc(g: ^Game, format: string, args: ..any) {
	say(g, fmt.tprintf(format, ..args))
}

// The three columns of a shop row: its name, the level and the price (on the temp allocator).
shop_row_text :: proc(g: ^Game, row: int) -> (name, level, cost: string) {
	kind, index := row_kind(row)
	switch kind {
	case .Start:
		if g.shop_sel == 0 && toggle_on(g.progress, .Auto_Start) {
			return fmt.tprintf("START RUN  %d", int((AUTO_START_MS - g.auto_start_ms + 999) / 1000)), "", ""
		}
		return "START RUN", "", ""
	case .Upgrade:
		u := Upgrade(index)
		if t, is_toggle := upgrade_toggle(u); is_toggle && toggle_unlocked(g.progress, t) {
			return UPGRADES[u].name, g.progress.auto_off[t] ? "OFF" : "ON", "GREEN SWITCHES"
		}
		have := g.progress.levels[u]
		cost = have >= UPGRADES[u].max_level ? "MAX" : fmt.tprintf("%d", next_cost(g.progress, u))
		return UPGRADES[u].name, fmt.tprintf("LV %d/%d", have, UPGRADES[u].max_level), cost
	case .Perk:
		k := Perk(index)
		if t, is_toggle := perk_toggle(k); is_toggle && toggle_unlocked(g.progress, t) {
			return PERKS[k].name, g.progress.auto_off[t] ? "OFF" : "ON", "GREEN SWITCHES"
		}
		have := g.progress.perks[k]
		cost = have >= PERKS[k].max_level ? "MAX" : fmt.tprintf("%d GEMS", next_perk_cost(g.progress, k))
		return PERKS[k].name, fmt.tprintf("LV %d/%d", have, PERKS[k].max_level), cost
	case .Prestige:
		gain := gems_for_prestige(g.progress.era_earned)
		if gain == 0 {
			return "PRESTIGE", "", fmt.tprintf("ERA %d/%d", g.progress.era_earned, next_gem_at(0))
		}
		return "PRESTIGE", "", fmt.tprintf("+%d GEMS", gain)
	}
	return "", "", ""
}

// Whether the player can afford the row's price right now (the start row is always fine).
row_affordable :: proc(g: ^Game, row: int) -> bool {
	kind, index := row_kind(row)
	switch kind {
	case .Start:
		return true
	case .Upgrade:
		u := Upgrade(index)
		return g.progress.levels[u] < UPGRADES[u].max_level && g.progress.coins >= next_cost(g.progress, u)
	case .Perk:
		k := Perk(index)
		return perk_affordable(g.progress, k)
	case .Prestige:
		return gems_for_prestige(g.progress.era_earned) > 0
	}
	return false
}

row_what :: proc(g: ^Game, row: int) -> string {
	kind, index := row_kind(row)
	switch kind {
	case .Start:
		for other in 1 ..< SHOP_ROWS - 1 {
			if row_affordable(g, other) {
				return "START THE NEXT RUN"
			}
		}
		return "NOTHING TO BUY YET: START A RUN"
	case .Upgrade:
		return UPGRADES[Upgrade(index)].what
	case .Perk:
		return PERKS[Perk(index)].what
	case .Prestige:
		gain := gems_for_prestige(g.progress.era_earned)
		if gain == 0 {
			return "ERA COINS TOWARD YOUR FIRST GEM"
		}
		return fmt.tprintf("NEXT GEM AT %d ERA COINS", next_gem_at(gain))
	}
	return ""
}

draw_shop :: proc(g: ^Game, r: ^cm.Renderer) {
	white, grey, gold := cm.Color{255, 255, 255}, cm.Color{110, 110, 110}, cm.Color{255, 221, 85}
	cm.draw_text(r, 8, 4, "SHOP", gold)
	coins := fmt.tprintf("COINS %d", g.progress.coins)
	cm.draw_text(r, cm.SCREEN_W - 8 - cm.text_width(coins), 4, coins, white)
	if g.new_best {
		cm.draw_text(r, 8, 14, fmt.tprintf("NEW BEST! +%d", g.last_run), gold)
	} else {
		cm.draw_text(r, 8, 14, fmt.tprintf("LAST RUN +%d   BEST %d", g.last_run, g.progress.best_run), grey)
	}
	gems := fmt.tprintf("GEMS %d", g.progress.gems)
	cm.draw_text(r, cm.SCREEN_W - 8 - cm.text_width(gems), 14, gems, cm.Color{120, 220, 255})
	for row in 0 ..< SHOP_ROWS {
		y := SHOP_TOP_Y + row * SHOP_ROW_H
		selected := row == g.shop_sel
		if selected {
			cm.renderer_fill_rect(r, 0, y - 2, cm.SCREEN_W, SHOP_ROW_H - 1, g.prestige_armed ? cm.Color{110, 0, 0} : cm.Color{0, 0, 90})
			cm.draw_text(r, 4, y, ">", gold)
		}
		name, level, cost := shop_row_text(g, row)
		kind, _ := row_kind(row)
		ink := row_affordable(g, row) ? white : grey
		cm.draw_text(r, 14, y, name, kind == .Start ? gold : ink)
		cm.draw_text(r, SHOP_LEVEL_X, y, level, ink)
		cm.draw_text(r, cm.SCREEN_W - 8 - cm.text_width(cost), y, cost, ink)
	}
	cm.draw_text(r, 14, SHOP_WHAT_Y, row_what(g, g.shop_sel), cm.Color{150, 190, 255})
	if g.message_ms > 0 {
		cm.draw_text(r, 14, SHOP_MESSAGE_Y, g.message, gold)
	}
}
