#+build !js
package game

import rt "anvil:anvil_runtime"
import "core:testing"

@(test)
test_flood_reach_stops_at_walls_and_ignores_walled_off_cells :: proc(t: ^testing.T) {
	// 5x3, X = wall:     . . X . .
	//                    . . X . .
	//                    . . X . .   the right two columns are cut off
	blocked := []bool{false, false, true, false, false, false, false, true, false, false, false, false, true, false, false}
	reach := flood_reach(5, 3, blocked, {0, 0})
	for y in 0 ..< 3 {
		for x in 0 ..< 5 {
			testing.expect_value(t, reach[y * 5 + x], x < 2)
		}
	}
	// a gap in the wall joins them
	blocked[1 * 5 + 2] = false
	reach = flood_reach(5, 3, blocked, {0, 0})
	for y in 0 ..< 3 {
		for x in 0 ..< 5 {
			testing.expect_value(t, reach[y * 5 + x], x != 2 || y == 1)
		}
	}
}

@(test)
test_flood_reach_from_a_wall_or_outside_reaches_nothing :: proc(t: ^testing.T) {
	blocked := []bool{false, true, false, false}
	for start in ([3][2]int{{1, 0}, {-1, 0}, {0, 2}}) {
		reach := flood_reach(2, 2, blocked, start)
		for r in reach {
			testing.expect(t, !r)
		}
	}
}

@(test)
test_everything_the_game_can_reach_in_the_real_room_is_what_the_thing_may_use :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	reach, width := player_reach(g)
	for c in rt.cells_with_tag(g.world, g.map_index, g.spawn_tag) {
		// the room has no walled-off floor, so every spawn cell that is not solid is reachable
		testing.expect_value(t, reach[c.y * width + c.x], !rt.cell_is_solid(g.world, g.map_index, c.x, c.y))
	}
	// the player's own cell is reached; a wall is not
	testing.expect(t, reach[5 * width + 2])
	testing.expect(t, !reach[0])
}
