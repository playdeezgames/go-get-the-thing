// Which cells can the player walk to? The Thing only appears where it can be got.
package game

import rt "anvil:anvil_runtime"

// The cells reachable from `start` by 4-way steps over cells that are not blocked. `blocked` is
// width*height long, row by row; a start that is blocked or outside reaches nothing.
flood_reach :: proc(width, height: int, blocked: []bool, start: [2]int, allocator := context.temp_allocator) -> []bool {
	reach := make([]bool, width * height, allocator)
	if start.x < 0 || start.y < 0 || start.x >= width || start.y >= height || blocked[start.y * width + start.x] {
		return reach
	}
	queue := make([dynamic][2]int, 0, width * height, context.temp_allocator)
	reach[start.y * width + start.x] = true
	append(&queue, start)
	for head := 0; head < len(queue); head += 1 {
		c := queue[head]
		for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			n := c + d
			if n.x < 0 || n.y < 0 || n.x >= width || n.y >= height {
				continue
			}
			i := n.y * width + n.x
			if !blocked[i] && !reach[i] {
				reach[i] = true
				append(&queue, n)
			}
		}
	}
	return reach
}

// The cells of the game's map the player can walk to from where it stands now.
player_reach :: proc(g: ^Game) -> (reach: []bool, width: int) {
	cols, rows, _ := rt.map_size(g.world, g.map_index)
	blocked := make([]bool, cols * rows, context.temp_allocator)
	for y in 0 ..< rows {
		for x in 0 ..< cols {
			blocked[y * cols + x] = rt.cell_is_solid(g.world, g.map_index, x, y)
		}
	}
	p := rt.play_position(&g.play, g.player)
	return flood_reach(cols, rows, blocked, {p.x, p.y}), cols
}
