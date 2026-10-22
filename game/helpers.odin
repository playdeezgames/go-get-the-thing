// Helpers: characters bought in the shop that walk to the nearest Thing and pick it up, on their own
// clock. They need no input: `run_helpers` is called from `update` while a run is being played.
package game

import rt "anvil:anvil_runtime"

MAX_HELPER_STEPS_PER_FRAME :: 8 // a long frame must not make a helper run a marathon

// Puts the bought helpers in the room (on free cells, apart from each other) and starts their clocks,
// staggered so they do not all step on the same frame. The unbought ones stay off the map.
start_helpers :: proc(g: ^Game) {
	n := min(helper_count(g.progress), g.helper_n)
	interval := helper_step_ms(g.progress)
	for i in 0 ..< n {
		place_on_free_cell(g, g.helpers[i])
		g.helper_clock[i] = interval * f64(i + 1) / f64(n + 1)
	}
}

run_helpers :: proc(g: ^Game, dt_ms: f64) {
	n := min(helper_count(g.progress), g.helper_n)
	interval := helper_step_ms(g.progress)
	for i in 0 ..< n {
		g.helper_clock[i] -= dt_ms
		for steps := 0; g.helper_clock[i] <= 0 && steps < MAX_HELPER_STEPS_PER_FRAME; steps += 1 {
			g.helper_clock[i] += interval
			helper_step(g, g.helpers[i])
		}
		g.helper_clock[i] = max(g.helper_clock[i], 0)
	}
}

// One step for a helper along the shortest path to the nearest Thing. With no path (the way is shut by
// other characters) it waits.
helper_step :: proc(g: ^Game, ci: int) {
	if !rt.play_position(&g.play, ci).placed {
		return
	}
	if dx, dy, ok := step_towards_nearest_thing(g, ci); ok {
		step_collecting(g, ci, dx, dy, CHANNEL_HELPERS)
	}
}

// The Thing a helper should aim for: helpers take the Things in turn, each the nearest one (straight
// line) that no earlier helper has taken, so they do not all crowd onto the same one. -1 when the
// character is not a helper, or every Thing is taken (then it aims for the nearest as before).
helper_target :: proc(g: ^Game, ci: int) -> int {
	n := min(helper_count(g.progress), g.helper_n)
	taken: [MAX_THINGS]bool
	for i in 0 ..< n {
		hp := rt.play_position(&g.play, g.helpers[i])
		if !hp.placed {
			continue
		}
		best, best_d := -1, 0
		for k in 0 ..< g.thing_n {
			tp := rt.play_position(&g.play, g.things[k])
			if taken[k] || !tp.placed {
				continue
			}
			if d := abs(tp.x - hp.x) + abs(tp.y - hp.y); best < 0 || d < best_d {
				best, best_d = k, d
			}
		}
		if best >= 0 {
			taken[best] = true
		}
		if g.helpers[i] == ci {
			return best >= 0 ? g.things[best] : -1
		}
	}
	return -1
}

// The first step (dx, dy) of a shortest walk from the character to the nearest Thing over cells that
// are not solid and not held by another character (a Thing's cell is the goal, so it is allowed).
// Breadth first with a fixed neighbour order, so the same world gives the same walk.
step_towards_nearest_thing :: proc(g: ^Game, ci: int) -> (dx, dy: int, ok: bool) {
	target := helper_target(g, ci)
	cols, rows, _ := rt.map_size(g.world, g.map_index)
	cells := cols * rows
	blocked := make([]bool, cells, context.temp_allocator)
	goal := make([]bool, cells, context.temp_allocator)
	for y in 0 ..< rows {
		for x in 0 ..< cols {
			blocked[y * cols + x] = rt.cell_is_solid(g.world, g.map_index, x, y)
		}
	}
	for other in rt.play_characters_in_map(&g.play, g.map_index) {
		p := rt.play_position(&g.play, other)
		i := p.y * cols + p.x
		if other == ci {
			continue
		}
		if rt.character_has_tag(g.world, other, g.thing_tag) {
			goal[i] = target < 0 || other == target // another helper's Thing is passed, not aimed at
		} else {
			blocked[i] = true
		}
	}
	me := rt.play_position(&g.play, ci)
	start := me.y * cols + me.x
	parent := make([]int, cells, context.temp_allocator)
	for i in 0 ..< cells {
		parent[i] = -1
	}
	parent[start] = start
	queue := make([dynamic]int, 0, cells, context.temp_allocator)
	append(&queue, start)
	for head := 0; head < len(queue); head += 1 {
		at := queue[head]
		if goal[at] {
			// walk back to the cell right after the start
			for parent[at] != start {
				at = parent[at]
			}
			return at % cols - me.x, at / cols - me.y, true
		}
		x, y := at % cols, at / cols
		for d in ([4][2]int{{0, -1}, {0, 1}, {-1, 0}, {1, 0}}) {
			nx, ny := x + d.x, y + d.y
			if nx < 0 || ny < 0 || nx >= cols || ny >= rows {
				continue
			}
			ni := ny * cols + nx
			if blocked[ni] || parent[ni] != -1 {
				continue
			}
			parent[ni] = at
			append(&queue, ni)
		}
	}
	return 0, 0, false
}
