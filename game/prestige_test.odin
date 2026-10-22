#+build !js
package game

import rt "anvil:anvil_runtime"
import cm "anvil:common"
import "core:testing"

// Select a shop row by kind (and index) with the commands a player would use.
go_to_row :: proc(g: ^Game, kind: Row_Kind, index := 0) {
	for row in 0 ..< SHOP_ROWS {
		if k, i := row_kind(row); k == kind && i == index {
			g.shop_sel = row
			return
		}
	}
}

@(test)
test_every_shop_row_has_a_kind_and_the_prestige_row_is_last :: proc(t: ^testing.T) {
	counts: [Row_Kind]int
	for row in 0 ..< SHOP_ROWS {
		kind, index := row_kind(row)
		counts[kind] += 1
		switch kind {
		case .Upgrade:
			testing.expect(t, index >= 0 && index < len(Upgrade))
		case .Perk:
			testing.expect(t, index >= 0 && index < len(Perk))
		case .Start, .Prestige:
		}
	}
	testing.expect_value(t, counts[.Start], 1)
	testing.expect_value(t, counts[.Upgrade], len(Upgrade))
	testing.expect_value(t, counts[.Perk], len(Perk))
	testing.expect_value(t, counts[.Prestige], 1)
	kind, _ := row_kind(SHOP_ROWS - 1)
	testing.expect_value(t, kind, Row_Kind.Prestige)
}

@(test)
test_a_run_adds_to_the_eras_earnings :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.score = 40
	update(g, 31_000)
	testing.expect_value(t, g.progress.era_earned, 40)
	handle_command(g, .Green)
	g.score = 2
	update(g, 31_000)
	testing.expect_value(t, g.progress.era_earned, 42)
}

@(test)
test_prestige_asks_first_then_does_it_and_says_what_it_gave :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	in_shop(g)
	g.progress = Progress{coins = 900, best_run = 50, era_earned = 4 * GEM_ERA_DIVISOR}
	g.progress.levels[.Helpers] = 2
	go_to_row(g, .Prestige)
	handle_command(g, .Green) // the first press only asks
	testing.expect(t, g.prestige_armed)
	testing.expect_value(t, g.progress.gems, 0)
	testing.expect_value(t, g.progress.coins, 900)
	handle_command(g, .Green)
	testing.expect(t, !g.prestige_armed)
	testing.expect_value(t, g.progress.gems, 2)
	testing.expect_value(t, g.progress.coins, 0)
	testing.expect_value(t, g.progress.levels[.Helpers], 0)
	testing.expect_value(t, g.progress.era_earned, 0)
	testing.expect_value(t, g.progress.best_run, 50)
	req, ok := take_audio(g)
	testing.expect(t, ok)
	testing.expect(t, raw_data(req.samples) == raw_data(g.prestige_pcm))
	text, saved := take_save(g)
	testing.expect(t, saved)
	back, parsed := progress_from_json(transmute([]u8)text)
	testing.expect(t, parsed)
	testing.expect_value(t, back, g.progress)
}

@(test)
test_moving_away_or_waiting_cancels_a_prestige_that_was_asked_for :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	in_shop(g)
	g.progress = Progress{coins = 900, era_earned = 4 * GEM_ERA_DIVISOR}
	go_to_row(g, .Prestige)
	handle_command(g, .Green)
	handle_command(g, .Up) // away
	testing.expect(t, !g.prestige_armed)
	go_to_row(g, .Prestige)
	handle_command(g, .Green) // asks again
	testing.expect(t, g.prestige_armed)
	update(g, SHOP_MESSAGE_MS + 1) // nobody answered
	testing.expect(t, !g.prestige_armed)
	handle_command(g, .Green) // so this only asks again
	testing.expect_value(t, g.progress.gems, 0)
	testing.expect_value(t, g.progress.coins, 900)
}

@(test)
test_prestige_with_too_little_earned_does_nothing :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	in_shop(g)
	g.progress = Progress{coins = 900, era_earned = GEM_ERA_DIVISOR - 1}
	go_to_row(g, .Prestige)
	handle_command(g, .Green)
	testing.expect(t, !g.prestige_armed)
	testing.expect_value(t, g.message, "EARN MORE COINS FIRST")
	testing.expect_value(t, g.progress.coins, 900)
}

@(test)
test_a_perk_is_bought_with_gems_and_a_refusal_says_gems :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	in_shop(g)
	go_to_row(g, .Perk)
	handle_command(g, .Green)
	testing.expect_value(t, g.message, "NOT ENOUGH GEMS")
	g.progress.gems = 5
	handle_command(g, .Green)
	testing.expect_value(t, g.progress.perks[.Time_Chance], 1)
	testing.expect_value(t, g.progress.gems, 3)
	testing.expect_value(t, g.message, "BOUGHT")
}

@(test)
test_a_thing_can_carry_extra_time_by_chance :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.progress.perks[.Time_Chance] = 10 // 50 percent
	hits := 0
	for _ in 0 ..< 400 {
		g.time_bonuses = 0
		g.ms_left = 20_000
		take_audio(g)
		rt.play_unplace(&g.play, g.thing)
		p := rt.play_position(&g.play, g.player)
		rt.play_place(&g.play, g.world, g.thing, g.map_index, p.x + 1, p.y)
		g.step_cooldown_ms = 0
		move_player(g, 1, 0)
		move_player(g, -1, 0) // back, so the next Thing can go beside the player again
		if g.ms_left > 20_000 {
			hits += 1
			testing.expect_value(t, g.ms_left, f64(20_000 + TIME_BONUS_MS))
			testing.expect_value(t, g.time_bonuses, 1)
			testing.expect(t, g.bonus_flash_ms > 0)
		}
	}
	testing.expect(t, hits > 140 && hits < 260) // about half of 400
}

@(test)
test_without_the_perk_no_time_is_ever_added_and_the_dice_are_not_rolled :: proc(t: ^testing.T) {
	a := started(9)
	b := started(9)
	defer finish(a)
	defer finish(b)
	for g in ([2]^Game{a, b}) {
		rt.play_place(&g.play, g.world, g.thing, g.map_index, 3, 5)
		move_player(g, 1, 0)
	}
	testing.expect_value(t, a.ms_left, a.round_ms)
	// the same seed gives the same Thing position: the (absent) perk drew nothing
	testing.expect_value(t, thing_at(a), thing_at(b))
	b.progress.perks[.Time_Chance] = 0
	testing.expect_value(t, a.rng, b.rng)
}

@(test)
test_a_run_gets_at_most_the_capped_time_bonuses_so_it_always_ends :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.progress.perks[.Time_Chance] = 20 // far above 100 percent: every Thing would add time
	g.progress.levels[.Helpers] = 4
	g.progress.levels[.Helper_Speed] = 8
	g.progress.levels[.More_Things] = 3
	start_run(g)
	for _ in 0 ..< 3000 {
		update(g, 100)
		if g.state != .Playing {
			break
		}
	}
	testing.expect_value(t, g.state, State.Shop) // the run ended
	testing.expect(t, g.time_bonuses <= time_bonus_cap(g.progress))
	testing.expect_value(t, g.time_bonuses, time_bonus_cap(g.progress))
}

@(test)
test_the_hud_shows_the_bonus_for_a_moment_and_the_shop_fits_every_row :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.bonus_flash_ms = BONUS_FLASH_MS
	_, _, label, _ := hud_text(g)
	testing.expect_value(t, label, "+5 SEC")
	testing.expect(t, cm.text_width(label) <= HUD_RIGHT.w - 4)
	update(g, BONUS_FLASH_MS + 1)
	_, _, label, _ = hud_text(g)
	testing.expect_value(t, label, "TIME")
	g.progress = Progress{coins = 999_999_999, gems = 999_999_999, era_earned = 999_999_999, best_run = 999_999_999}
	for row in 0 ..< SHOP_ROWS {
		name, level, cost := shop_row_text(g, row)
		for s in ([3]string{name, level, cost}) {
			testing.expect(t, cm.text_is_drawable(s))
		}
		testing.expect(t, SHOP_LEVEL_X > 14 + cm.text_width(name))
		testing.expect(t, SHOP_LEVEL_X + cm.text_width(level) < cm.SCREEN_W - 8 - cm.text_width(cost))
		testing.expect(t, cm.text_is_drawable(row_what(g, row)) && cm.text_width(row_what(g, row)) <= cm.SCREEN_W - 28)
	}
	testing.expect(t, SHOP_TOP_Y + SHOP_ROWS * SHOP_ROW_H <= SHOP_WHAT_Y)
	// the longest note the prestige row can make fits the screen
	sayf(g, "PRESS AGAIN: +%d GEMS, COINS AND UPGRADES RESET", 99_999)
	testing.expect(t, cm.text_width(g.message) <= cm.SCREEN_W - 28)
	testing.expect(t, cm.text_is_drawable(g.message))
}

@(test)
test_the_time_bonus_cap_grows_with_the_perk_level :: proc(t: ^testing.T) {
	p: Progress
	testing.expect_value(t, time_bonus_cap(p), TIME_BONUS_CAP_BASE)
	p.perks[.Time_Chance] = 10
	testing.expect_value(t, time_bonus_cap(p), TIME_BONUS_CAP_BASE + 10 * TIME_BONUS_CAP_PER_LEVEL)
}

@(test)
test_a_thing_can_pay_extra_coins_by_chance :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.progress.perks[.Lucky_Coins] = 5 // 20 percent
	hits := 0
	for _ in 0 ..< 500 {
		g.score = 0
		rt.play_unplace(&g.play, g.thing)
		p := rt.play_position(&g.play, g.player)
		rt.play_place(&g.play, g.world, g.thing, g.map_index, p.x + 1, p.y)
		g.step_cooldown_ms = 0
		move_player(g, 1, 0)
		earned := g.score // before stepping back, which may land on the respawned Thing
		move_player(g, -1, 0)
		base := coins_per_thing(g.progress, g.points_per_thing)
		if earned != base {
			hits += 1
			testing.expect_value(t, earned, base * LUCKY_MULTIPLIER)
		}
	}
	testing.expect(t, hits > 60 && hits < 140) // about 100 of 500
}
