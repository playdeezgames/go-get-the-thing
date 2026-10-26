#+build !js
package game

import rt "anvil:anvil_runtime"
import "core:testing"

@(test)
test_auto_start_counts_down_on_the_start_row_and_starts_the_run :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	in_shop(g)
	update(g, 20_000)
	testing.expect_value(t, g.state, State.Shop) // not owned: nothing happens
	g.progress.levels[.Auto_Start] = 1
	update(g, AUTO_START_MS - 1000)
	testing.expect_value(t, g.state, State.Shop)
	name, _, _ := shop_row_text(g, 0)
	testing.expect_value(t, name, "START RUN  1")
	update(g, 1000)
	testing.expect_value(t, g.state, State.Playing)
}

@(test)
test_moving_off_start_run_cancels_auto_start_and_returning_restarts_it :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	in_shop(g)
	g.progress.levels[.Auto_Start] = 1
	update(g, 10_000)
	handle_command(g, .Down)
	update(g, 20_000)
	testing.expect_value(t, g.state, State.Shop)
	handle_command(g, .Up)
	update(g, 10_000)
	testing.expect_value(t, g.state, State.Shop) // a fresh 15 seconds, not the old 10
	update(g, 5_000)
	testing.expect_value(t, g.state, State.Playing)
}

@(test)
test_a_switched_off_automation_does_nothing :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	in_shop(g)
	g.progress.levels[.Auto_Start] = 1
	g.progress.auto_off[.Auto_Start] = true
	update(g, 60_000)
	testing.expect_value(t, g.state, State.Shop)
}

@(test)
test_green_on_an_owned_automation_switches_it :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	in_shop(g)
	g.progress.perks[.Auto_Play] = 1
	g.shop_sel = 1 + len(Upgrade) + int(Perk.Auto_Play)
	handle_command(g, .Green)
	testing.expect(t, g.progress.auto_off[.Auto_Play])
	testing.expect(t, !toggle_on(g.progress, .Auto_Play))
	handle_command(g, .Green)
	testing.expect(t, toggle_on(g.progress, .Auto_Play))
	testing.expect_value(t, g.progress.perks[.Auto_Play], 1) // switching never buys or sells
}

@(test)
test_auto_buy_buys_a_random_perk_after_ten_idle_seconds :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	in_shop(g)
	g.progress.perks[.Auto_Buy] = 1
	update(g, 60_000)
	testing.expect_value(t, g.progress.perks[.Time_Chance] + g.progress.perks[.Lucky_Coins], 0) // no gems: no timer
	g.progress.gems = 10
	update(g, AUTO_BUY_IDLE_MS - 100)
	testing.expect_value(t, g.progress.gems, 10)
	handle_command(g, .Down) // any input starts the wait over
	update(g, AUTO_BUY_IDLE_MS - 100)
	testing.expect_value(t, g.progress.gems, 10)
	update(g, 200)
	testing.expect(t, g.progress.gems < 10)
	testing.expect(t, g.save_requested)
}

@(test)
test_auto_play_collects_and_the_players_input_pauses_it :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.progress.perks[.Auto_Play] = 1
	g.progress.levels[.Player_Speed] = 0
	start_run(g)
	before := rt.play_position(&g.play, g.player)
	update(g, 16)
	after := rt.play_position(&g.play, g.player)
	testing.expect(t, before.x != after.x || before.y != after.y)
	// a keypress pauses the autopilot for a moment
	update(g, 300)
	handle_command(g, .Up)
	update(g, 300)
	testing.expect(t, g.auto_play_pause_ms > 0)
	// the whole run, left alone, earns coins
	for g.state == .Playing {
		update(g, 16)
		free_all(context.temp_allocator)
	}
	testing.expect(t, g.last_run > 0)
}

@(test)
test_the_result_screen_moves_on_by_itself_with_auto_start :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.progress.levels[.Auto_Start] = 1
	start_run(g)
	g.ms_left = 1
	update(g, 16)
	testing.expect_value(t, g.state, State.Result)
	update(g, RESULT_AUTO_MS + 1)
	testing.expect_value(t, g.state, State.Shop)
}
