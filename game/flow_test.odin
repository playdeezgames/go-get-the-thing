#+build !js
package game

import rt "anvil:anvil_runtime"
import cm "anvil:common"
import "core:testing"

in_shop :: proc(g: ^Game) {
	g.state = .Shop
	g.shop_sel = 0
}

things_in_room :: proc(g: ^Game) -> (n: int) {
	for i in 0 ..< g.thing_n {
		if rt.play_position(&g.play, g.things[i]).placed {
			n += 1
		}
	}
	return
}

@(test)
test_the_shop_list_wraps_and_start_run_is_the_first_row :: proc(t: ^testing.T) {
	g := new(Game)
	defer finish(g)
	init(g)
	handle_command(g, .Green)
	testing.expect_value(t, g.state, State.Shop)
	testing.expect_value(t, g.shop_sel, 0)
	handle_command(g, .Up)
	testing.expect_value(t, g.shop_sel, SHOP_ROWS - 1) // wraps to the last upgrade
	handle_command(g, .Down)
	testing.expect_value(t, g.shop_sel, 0)
	handle_command(g, .Down)
	testing.expect_value(t, g.shop_sel, 1)
}

@(test)
test_buying_in_the_shop_spends_coins_plays_a_sound_and_asks_for_a_save :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.progress.coins = 15
	in_shop(g)
	take_save(g) // the run-less start asked for nothing yet
	handle_command(g, .Down) // THING VALUE costs 12
	handle_command(g, .Green)
	testing.expect_value(t, g.progress.coins, 3)
	testing.expect_value(t, g.progress.levels[.Thing_Value], 1)
	testing.expect_value(t, g.message, "BOUGHT")
	req, ok := take_audio(g)
	testing.expect(t, ok)
	testing.expect(t, raw_data(req.samples) == raw_data(g.buy_pcm))
	text, saved := take_save(g)
	testing.expect(t, saved)
	back, parsed := progress_from_json(transmute([]u8)text)
	testing.expect(t, parsed)
	testing.expect_value(t, back, g.progress)
}

@(test)
test_a_refused_purchase_says_why_and_changes_nothing :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	in_shop(g)
	handle_command(g, .Down)
	before := g.progress
	handle_command(g, .Green) // no coins
	testing.expect_value(t, g.progress, before)
	testing.expect_value(t, g.message, "NOT ENOUGH COINS")
	testing.expect(t, g.message_ms > 0)
	_, played := take_audio(g)
	testing.expect(t, !played)
	update(g, SHOP_MESSAGE_MS + 1)
	testing.expect_value(t, g.message_ms, f64(0))
	g.progress.levels[.Thing_Value] = UPGRADES[.Thing_Value].max_level
	g.progress.coins = 1_000_000
	handle_command(g, .Green)
	testing.expect_value(t, g.message, "ALREADY AT THE MAXIMUM")
	testing.expect_value(t, g.progress.coins, 1_000_000)
}

@(test)
test_thing_value_changes_what_a_pickup_pays :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.progress.levels[.Thing_Value] = 2 // 3 coins a Thing
	rt.play_place(&g.play, g.world, g.thing, g.map_index, 3, 5)
	move_player(g, 1, 0)
	testing.expect_value(t, g.score, 3)
}

@(test)
test_run_length_changes_the_clock_and_more_things_fill_the_room :: proc(t: ^testing.T) {
	g := new(Game)
	defer finish(g)
	init(g)
	g.progress.levels[.Run_Length] = 2
	g.progress.levels[.More_Things] = 3
	handle_command(g, .Green)
	handle_command(g, .Green)
	testing.expect_value(t, g.ms_left, f64(40_000))
	testing.expect_value(t, things_in_room(g), 4)
	// they are all on different, reachable, free cells
	seen: map[[2]int]bool
	defer delete(seen)
	reach, width := player_reach(g)
	for i in 0 ..< g.thing_n {
		p := rt.play_position(&g.play, g.things[i])
		testing.expect(t, !seen[{p.x, p.y}])
		seen[{p.x, p.y}] = true
		testing.expect(t, reach[p.y * width + p.x])
		testing.expect(t, [2]int{p.x, p.y} != player_at(g))
	}
}

@(test)
test_any_thing_can_be_picked_up_and_comes_back :: proc(t: ^testing.T) {
	g := new(Game)
	defer finish(g)
	init(g)
	g.progress.levels[.More_Things] = 3
	handle_command(g, .Green)
	handle_command(g, .Green)
	other := g.things[2]
	rt.play_unplace(&g.play, other)
	rt.play_place(&g.play, g.world, other, g.map_index, 3, 5)
	move_player(g, 1, 0)
	testing.expect_value(t, g.score, 1)
	testing.expect(t, rt.play_position(&g.play, other).placed)
	testing.expect_value(t, things_in_room(g), 4)
}

@(test)
test_the_player_cannot_step_faster_than_the_upgrade_allows :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	handle_command(g, .Right)
	testing.expect_value(t, player_at(g), [2]int{3, 5})
	handle_command(g, .Right) // too soon: 250 ms between steps at level 0
	testing.expect_value(t, player_at(g), [2]int{3, 5})
	update(g, 249)
	handle_command(g, .Right)
	testing.expect_value(t, player_at(g), [2]int{3, 5})
	update(g, 2)
	handle_command(g, .Right)
	testing.expect_value(t, player_at(g), [2]int{4, 5})
	// a step into a wall costs no time
	g.step_cooldown_ms = 0
	g.progress.levels[.Player_Speed] = 8
	for _ in 0 ..< 3 {
		handle_command(g, .Right)
		update(g, 60)
	}
	testing.expect_value(t, player_at(g), [2]int{5, 5})
	handle_command(g, .Right) // the wall at x = 6
	handle_command(g, .Left) // not held up by the refused step
	testing.expect_value(t, player_at(g), [2]int{4, 5})
}

@(test)
test_the_shop_draws_every_row_inside_the_screen :: proc(t: ^testing.T) {
	g := new(Game)
	defer finish(g)
	init(g)
	g.progress.coins = 999_999_999
	g.progress.best_run = 999_999_999
	g.last_run = 999_999_999
	g.progress.levels[.Thing_Value] = 20
	for row in 0 ..< SHOP_ROWS {
		name, level, cost := shop_row_text(g, row)
		for s in ([3]string{name, level, cost}) {
			testing.expect(t, cm.text_is_drawable(s))
		}
		testing.expect(t, SHOP_LEVEL_X > 14 + cm.text_width(name)) // the name stops before the level column
		testing.expect(t, SHOP_LEVEL_X + cm.text_width(level) < cm.SCREEN_W - 8 - cm.text_width(cost))
	}
	testing.expect(t, SHOP_TOP_Y + SHOP_ROWS * SHOP_ROW_H <= SHOP_WHAT_Y)
	testing.expect(t, SHOP_MESSAGE_Y + cm.GLYPH_H <= PAD_STRIP.y)
	for u in Upgrade {
		testing.expect(t, cm.text_width(UPGRADES[u].what) <= cm.SCREEN_W - 28)
	}
	for s in ([]string{"NOT ENOUGH COINS", "ALREADY AT THE MAXIMUM", "BOUGHT"}) {
		testing.expect(t, cm.text_is_drawable(s) && cm.text_width(s) <= cm.SCREEN_W - 28)
	}
}
