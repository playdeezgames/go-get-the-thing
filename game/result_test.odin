#+build !js
package game

import rt "anvil:anvil_runtime"
import "core:testing"

// Waits out the result screen's input lock and moves on to the shop.
leave_result :: proc(g: ^Game) {
	update(g, RESULT_LOCK_MS + 1)
	handle_command(g, .Green)
	assert(g.state == .Shop)
}

@(test)
test_a_run_ends_on_the_result_screen_and_it_ignores_input_at_first :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.ms_left = 1
	update(g, 5)
	testing.expect_value(t, g.state, State.Result)
	handle_command(g, .Green)
	handle_command(g, .Red)
	testing.expect_value(t, g.state, State.Result) // too soon
	update(g, RESULT_LOCK_MS + 1)
	handle_command(g, .Right)
	testing.expect_value(t, g.state, State.Result) // directions do nothing here
	handle_command(g, .Red)
	testing.expect_value(t, g.state, State.Shop)
	testing.expect_value(t, g.shop_sel, 0)
}

@(test)
test_the_result_splits_the_run_between_the_player_and_the_helpers :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.points_per_thing = 5
	// the player walks onto a Thing: put one right next to them
	rt.play_place(&g.play, g.world, g.thing, g.map_index, player_at(g).x + 1, player_at(g).y)
	testing.expect_value(t, move_player(g, 1, 0), rt.Move_Result.Moved)
	testing.expect_value(t, g.run_things[0], 1)
	testing.expect(t, g.run_coins[0] > 0)
	testing.expect_value(t, g.run_things[1], 0)
	testing.expect_value(t, g.run_coins[0], g.score)
	start_run(g)
	testing.expect_value(t, g.run_things, [2]int{})
	testing.expect_value(t, g.run_coins, [2]int{})
}
