#+build !js
package game

import rt "anvil:anvil_runtime"
import "core:testing"

@(test)
test_the_embedded_world_starts_the_game :: proc(t: ^testing.T) {
	g: Game
	init(&g)
	defer destroy(&g)
	testing.expect_value(t, g.error, "")
	cols, rows, _ := rt.map_size(g.world, g.map_index)
	testing.expect_value(t, cols, 20)
	testing.expect_value(t, rows, 11)
	testing.expect(t, g.thing != g.player)
	pos := rt.play_position(&g.play, g.player)
	testing.expect(t, !rt.cell_is_solid(g.world, g.map_index, pos.x, pos.y))
	pos = rt.play_position(&g.play, g.thing)
	testing.expect(t, rt.cell_has_tag(g.world, g.map_index, pos.x, pos.y, g.spawn_tag))
}

@(test)
test_there_are_spawn_cells_to_put_the_thing_on :: proc(t: ^testing.T) {
	g: Game
	init(&g)
	defer destroy(&g)
	testing.expect(t, len(rt.cells_with_tag(g.world, g.map_index, g.spawn_tag)) > 1)
}
