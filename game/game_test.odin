#+build !js
package game

import rt "anvil:anvil_runtime"
import cm "anvil:common"
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

// --- rules -----------------------------------------------------------------------------------------

started :: proc(seed: u64 = 1) -> ^Game {
	g := new(Game)
	init(g)
	set_seed(g, seed)
	handle_command(g, .Green)
	return g
}

finish :: proc(g: ^Game) {
	destroy(g)
	free(g)
}

player_at :: proc(g: ^Game) -> [2]int {
	p := rt.play_position(&g.play, g.player)
	return {p.x, p.y}
}

thing_at :: proc(g: ^Game) -> [2]int {
	p := rt.play_position(&g.play, g.thing)
	return {p.x, p.y}
}

@(test)
test_the_game_waits_on_the_title_until_green :: proc(t: ^testing.T) {
	g := new(Game)
	defer finish(g)
	init(g)
	testing.expect_value(t, g.state, State.Title)
	before := player_at(g)
	handle_command(g, .Right)
	testing.expect_value(t, player_at(g), before)
	update(g, 1000)
	testing.expect_value(t, g.ms_left, f64(30_000))
	handle_command(g, .Green)
	testing.expect_value(t, g.state, State.Playing)
}

@(test)
test_the_player_steps_one_cell_and_walls_stop_it :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	testing.expect_value(t, player_at(g), [2]int{2, 5})
	testing.expect_value(t, move_player(g, 1, 0), rt.Move_Result.Moved)
	testing.expect_value(t, player_at(g), [2]int{3, 5})
	for _ in 0 ..< 5 {
		move_player(g, -1, 0)
	}
	testing.expect_value(t, player_at(g), [2]int{1, 5}) // the exterior wall is at x = 0
	testing.expect_value(t, move_player(g, -1, 0), rt.Move_Result.Solid)
	// the interior wall at x = 6, y = 2..6
	for _ in 0 ..< 5 {
		move_player(g, 1, 0)
	}
	testing.expect_value(t, player_at(g), [2]int{5, 5})
	testing.expect_value(t, move_player(g, 1, 0), rt.Move_Result.Solid)
}

@(test)
test_walking_onto_the_thing_scores_and_moves_it :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	rt.play_place(&g.play, g.world, g.thing, g.map_index, 3, 5)
	testing.expect_value(t, move_player(g, 1, 0), rt.Move_Result.Moved)
	testing.expect_value(t, g.score, 1)
	testing.expect_value(t, player_at(g), [2]int{3, 5})
	testing.expect(t, thing_at(g) != player_at(g))
	testing.expect(t, rt.play_position(&g.play, g.thing).placed)
}

@(test)
test_the_thing_always_reappears_on_a_free_spawn_cell :: proc(t: ^testing.T) {
	g := started(7)
	defer finish(g)
	spawn := rt.cells_with_tag(g.world, g.map_index, g.spawn_tag)
	for _ in 0 ..< 300 {
		// put the thing next to the player, on a free cell, and walk onto it
		for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			p := player_at(g)
			if res, _, _ := rt.play_can_step(&g.play, g.world, g.player, d.x, d.y); res == .Moved {
				rt.play_place(&g.play, g.world, g.thing, g.map_index, p.x + d.x, p.y + d.y)
				move_player(g, d.x, d.y)
				break
			}
		}
		at := thing_at(g)
		testing.expect(t, !rt.cell_is_solid(g.world, g.map_index, at.x, at.y))
		testing.expect(t, at != player_at(g))
		found := false
		for c in spawn {
			found ||= c == at
		}
		testing.expect(t, found)
	}
	testing.expect_value(t, g.score, 300)
}

@(test)
test_points_per_thing_comes_from_the_world :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	testing.expect_value(t, g.points_per_thing, 1)
	testing.expect_value(t, g.round_ms, f64(30_000))
}

@(test)
test_the_timer_ends_the_round_and_green_plays_again :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.score = 3
	update(g, 29_900) // far more than one frame: the frontends clamp, the game just counts
	testing.expect_value(t, g.state, State.Playing)
	testing.expect_value(t, g.ms_left, f64(100))
	update(g, 250)
	testing.expect_value(t, g.state, State.Game_Over)
	testing.expect_value(t, g.ms_left, f64(0))
	testing.expect_value(t, g.score, 3)
	before := player_at(g)
	testing.expect_value(t, move_player(g, 1, 0), rt.Move_Result.Not_Placed)
	handle_command(g, .Right)
	testing.expect_value(t, player_at(g), before)
	handle_command(g, .Green)
	testing.expect_value(t, g.state, State.Playing)
	testing.expect_value(t, g.score, 0)
	testing.expect_value(t, g.ms_left, g.round_ms)
	testing.expect_value(t, player_at(g), [2]int{2, 5})
}

@(test)
test_the_same_seed_gives_the_same_things :: proc(t: ^testing.T) {
	a := started(42)
	b := started(42)
	defer finish(a)
	defer finish(b)
	for i in 0 ..< 20 {
		for g in ([2]^Game{a, b}) {
			rt.play_place(&g.play, g.world, g.thing, g.map_index, player_at(g).x + 1, player_at(g).y)
			move_player(g, 1, 0)
			move_player(g, -1, 0)
		}
		testing.expect_value(t, thing_at(a), thing_at(b))
	}
}

@(test)
test_the_clock_only_runs_while_playing :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	update(g, 0)
	update(g, -5) // a bad step counts as nothing
	testing.expect_value(t, g.ms_left, g.round_ms)
}

@(test)
test_a_pickup_plays_its_sound_and_the_end_of_the_round_plays_game_over :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	_, any := take_audio(g)
	testing.expect(t, !any) // silence until something happens
	rt.play_place(&g.play, g.world, g.thing, g.map_index, 3, 5)
	move_player(g, 1, 0)
	req, ok := take_audio(g)
	testing.expect(t, ok)
	testing.expect_value(t, req.action, cm.Audio_Action.Play)
	testing.expect_value(t, req.channel, CHANNEL_EFFECTS)
	testing.expect(t, len(req.samples) > 0)
	testing.expect(t, raw_data(req.samples) == raw_data(g.pickup_pcm))
	_, more := take_audio(g)
	testing.expect(t, !more)
	update(g, 31_000)
	req, ok = take_audio(g)
	testing.expect(t, ok)
	testing.expect(t, raw_data(req.samples) == raw_data(g.over_pcm))
	update(g, 1000) // already over: no second sound
	_, more = take_audio(g)
	testing.expect(t, !more)
}
