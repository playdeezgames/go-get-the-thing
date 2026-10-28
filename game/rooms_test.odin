#+build !js
package game

import rt "anvil:anvil_runtime"
import "core:testing"

@(test)
test_rooms_open_as_the_best_run_grows :: proc(t: ^testing.T) {
	p: Progress
	testing.expect_value(t, rooms_unlocked(p), 1)
	p.best_run = 30
	testing.expect_value(t, rooms_unlocked(p), 2)
	p.best_run = 300
	testing.expect_value(t, rooms_unlocked(p), len(ROOMS))
}

@(test)
test_with_one_room_open_no_dice_are_rolled :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	rng := g.rng
	testing.expect_value(t, pick_room(g), 0)
	testing.expect_value(t, g.rng, rng)
}

@(test)
test_every_room_starts_the_player_on_a_start_cell_with_a_reachable_thing_and_helpers :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.progress.best_run = 1_000_000
	g.progress.levels[.Helpers] = UPGRADES[.Helpers].max_level
	g.progress.levels[.More_Things] = UPGRADES[.More_Things].max_level
	for room in 0 ..< len(ROOMS) {
		rt.play_init(&g.play, g.world)
		enter_room(g, room)
		start_helpers(g)
		for i in 1 ..< thing_count(g.progress) {
			place_on_free_cell(g, g.things[i])
		}
		testing.expect_value(t, g.map_index, g.room_maps[room])
		p := rt.play_position(&g.play, g.player)
		testing.expect(t, p.placed && rt.cell_has_tag(g.world, g.map_index, p.x, p.y, g.start_tag))
		reach, width := player_reach(g)
		for ci in g.things[:thing_count(g.progress)] {
			tp := rt.play_position(&g.play, ci)
			testing.expectf(t, tp.placed && reach[tp.y * width + tp.x], "room %s: Thing %d", ROOMS[room].name, ci)
		}
		for ci in g.helpers[:g.helper_n] {
			hp := rt.play_position(&g.play, ci)
			testing.expectf(t, hp.placed && reach[hp.y * width + hp.x], "room %s: helper %d", ROOMS[room].name, ci)
		}
	}
}

@(test)
test_every_room_floor_can_be_walked_to_from_the_start :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	for room in 0 ..< len(ROOMS) {
		rt.play_init(&g.play, g.world)
		enter_room(g, room)
		reach, width := player_reach(g)
		cols, rows, _ := rt.map_size(g.world, g.map_index)
		for y in 0 ..< rows {
			for x in 0 ..< cols {
				if !rt.cell_is_solid(g.world, g.map_index, x, y) {
					testing.expectf(t, reach[y * width + x], "room %s: (%d,%d) is walled off", ROOMS[room].name, x, y)
				}
			}
		}
	}
}

@(test)
test_a_run_that_opens_a_room_says_so :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.score = 40
	finish_run(g)
	testing.expect(t, g.new_room)
	g.state = .Playing
	g.score = 45 // a better run, but no new room
	finish_run(g)
	testing.expect(t, !g.new_room)
}
