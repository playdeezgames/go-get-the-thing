#+build !js
package game

import rt "anvil:anvil_runtime"
import "core:testing"

run_with :: proc(helpers, helper_speed, more_things: int) -> ^Game {
	g := new(Game)
	init(g)
	set_seed(g, 5)
	g.progress.levels[.Helpers] = helpers
	g.progress.levels[.Helper_Speed] = helper_speed
	g.progress.levels[.More_Things] = more_things
	handle_command(g, .Green)
	handle_command(g, .Green)
	return g
}

// Puts a character on exactly this cell, taking it off the map first. True if it was placed.
put :: proc(g: ^Game, ci, x, y: int) -> bool {
	rt.play_unplace(&g.play, ci)
	return rt.play_place(&g.play, g.world, ci, g.map_index, x, y) == .Placed
}

where_is :: proc(g: ^Game, ci: int) -> [2]int {
	p := rt.play_position(&g.play, ci)
	return {p.x, p.y}
}

placed :: proc(g: ^Game, ci: int) -> bool {
	return rt.play_position(&g.play, ci).placed
}

distance :: proc(a, b: [2]int) -> int {
	return abs(a.x - b.x) + abs(a.y - b.y)
}

@(test)
test_there_are_no_helpers_until_one_is_bought :: proc(t: ^testing.T) {
	g := run_with(0, 0, 0)
	defer finish(g)
	for i in 0 ..< g.helper_n {
		testing.expect(t, !placed(g, g.helpers[i]))
	}
	update(g, 100)
	update(g, 100)
	testing.expect_value(t, g.score, 0)
}

@(test)
test_bought_helpers_start_apart_on_free_cells_and_the_rest_stay_off_the_map :: proc(t: ^testing.T) {
	g := run_with(3, 0, 0)
	defer finish(g)
	seen: map[[2]int]bool
	defer delete(seen)
	reach, width := player_reach(g)
	for i in 0 ..< g.helper_n {
		testing.expect_value(t, placed(g, g.helpers[i]), i < 3)
		if i < 3 {
			at := where_is(g, g.helpers[i])
			testing.expect(t, !seen[at])
			seen[at] = true
			testing.expect(t, reach[at.y * width + at.x])
			testing.expect(t, at != where_is(g, g.player))
			testing.expect(t, at != where_is(g, g.thing))
		}
	}
}

@(test)
test_a_helper_steps_toward_the_nearest_thing_on_its_own_clock :: proc(t: ^testing.T) {
	g := run_with(1, 0, 0)
	defer finish(g)
	h := g.helpers[0]
	testing.expect(t, put(g, h, 10, 8))
	testing.expect(t, put(g, g.thing, 14, 8))
	g.helper_clock[0] = 600 // the base step is 600 ms
	update(g, 100)
	update(g, 100)
	update(g, 100)
	update(g, 100)
	update(g, 100)
	testing.expect_value(t, where_is(g, h), [2]int{10, 8}) // 500 ms: not yet
	update(g, 100)
	testing.expect_value(t, where_is(g, h), [2]int{11, 8}) // 600 ms: one cell closer
	update(g, 100)
	testing.expect_value(t, where_is(g, h), [2]int{11, 8})
}

@(test)
test_a_helper_picks_up_a_thing_pays_the_player_and_the_thing_comes_back :: proc(t: ^testing.T) {
	g := run_with(1, 8, 0) // fast: a step every 120 ms
	defer finish(g)
	g.progress.levels[.Thing_Value] = 1 // 2 coins
	h := g.helpers[0]
	testing.expect(t, put(g, h, 10, 8))
	testing.expect(t, put(g, g.thing, 11, 8))
	g.helper_clock[0] = 0
	update(g, 1)
	testing.expect_value(t, g.score, 2)
	testing.expect_value(t, where_is(g, h), [2]int{11, 8})
	testing.expect(t, placed(g, g.thing))
	testing.expect(t, where_is(g, g.thing) != [2]int{11, 8})
	req, ok := take_audio(g)
	testing.expect(t, ok)
	testing.expect_value(t, req.channel, CHANNEL_HELPERS) // not the player's channel
}

@(test)
test_a_helper_walks_around_a_wall_to_reach_a_thing :: proc(t: ^testing.T) {
	g := run_with(1, 8, 0)
	defer finish(g)
	h := g.helpers[0]
	// the wall at x = 6 runs from y = 2 to y = 6: the way from (5, 4) to (8, 4) goes round it
	testing.expect(t, put(g, h, 5, 4))
	testing.expect(t, put(g, g.thing, 8, 4))
	g.helper_clock[0] = 0
	for _ in 0 ..< 60 {
		update(g, 100)
		at := where_is(g, h)
		testing.expect(t, !rt.cell_is_solid(g.world, g.map_index, at.x, at.y))
		if g.score > 0 {
			break
		}
	}
	testing.expect_value(t, g.score, 1)
}

@(test)
test_a_helper_with_no_way_through_waits :: proc(t: ^testing.T) {
	g := run_with(1, 8, 0)
	defer finish(g)
	h := g.helpers[0]
	// in the corner (1, 1), with the player right beside it: the Thing below it is still reached
	testing.expect(t, put(g, h, 1, 1))
	testing.expect(t, put(g, g.player, 2, 1))
	testing.expect(t, put(g, g.thing, 1, 2))
	g.helper_clock[0] = 0
	update(g, 1)
	testing.expect_value(t, g.score, 1)
	// and with the Thing off the map there is nothing to walk to
	rt.play_unplace(&g.play, g.thing)
	before := where_is(g, h)
	g.helper_clock[0] = 0
	update(g, 1)
	testing.expect_value(t, where_is(g, h), before)
}

@(test)
test_helpers_never_share_a_cell_or_stand_in_a_wall_and_they_do_earn :: proc(t: ^testing.T) {
	g := run_with(4, 8, 3)
	defer finish(g)
	for _ in 0 ..< 400 { // 40 seconds of frames, in a 30 + s run
		update(g, 100)
		if g.state != .Playing {
			break
		}
		seen: map[[2]int]bool
		defer delete(seen)
		for ci in 0 ..< rt.character_count(g.world) {
			if !placed(g, ci) {
				continue
			}
			at := where_is(g, ci)
			testing.expect(t, !seen[at])
			seen[at] = true
			testing.expect(t, !rt.cell_is_solid(g.world, g.map_index, at.x, at.y))
		}
		testing.expect_value(t, things_in_room(g), 4) // every picked-up Thing comes back
	}
	testing.expect(t, g.score >= 5) // four fast helpers on four Things earn plenty
}

@(test)
test_a_long_frame_does_not_make_a_helper_run_a_marathon :: proc(t: ^testing.T) {
	g := run_with(1, 8, 0)
	defer finish(g)
	h := g.helpers[0]
	testing.expect(t, put(g, h, 1, 8))
	testing.expect(t, put(g, g.thing, 18, 8))
	g.helper_clock[0] = 0
	update(g, 10_000) // far longer than a real frame (the frontends clamp to 100 ms)
	testing.expect(t, distance(where_is(g, h), [2]int{1, 8}) <= MAX_HELPER_STEPS_PER_FRAME + 1)
}

@(test)
test_two_helpers_aim_for_different_things :: proc(t: ^testing.T) {
	g := run_with(2, 0, 1)
	defer finish(g)
	a, b := g.things[0], g.things[1]
	testing.expect(t, placed(g, a) && placed(g, b))
	t0 := helper_target(g, g.helpers[0])
	t1 := helper_target(g, g.helpers[1])
	testing.expect(t, t0 >= 0 && t1 >= 0)
	testing.expect(t, t0 != t1)
}
