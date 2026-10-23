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
	testing.expect_value(t, rows, 10)
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
	handle_command(g, .Green) // the title -> the shop
	handle_command(g, .Green) // START RUN
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
	testing.expect_value(t, g.state, State.Shop)
	handle_command(g, .Green) // START RUN is the highlighted row
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
test_the_timer_ends_the_run_banks_the_coins_and_the_shop_starts_the_next :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	g.score = 3
	update(g, 29_900) // far more than one frame: the frontends clamp, the game just counts
	testing.expect_value(t, g.state, State.Playing)
	testing.expect_value(t, g.ms_left, f64(100))
	update(g, 250)
	testing.expect_value(t, g.state, State.Result)
	testing.expect_value(t, g.ms_left, f64(0))
	testing.expect_value(t, g.progress.coins, 3) // the run's coins were banked
	testing.expect_value(t, g.progress.best_run, 3)
	testing.expect_value(t, g.last_run, 3)
	before := player_at(g)
	testing.expect_value(t, move_player(g, 1, 0), rt.Move_Result.Not_Placed)
	leave_result(g)
	handle_command(g, .Right) // in the shop this is not a step
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

Frame_Count :: struct {
	clears, fills, presents: int,
}

@(test)
test_every_frame_is_presented_once :: proc(t: ^testing.T) {
	g := new(Game)
	defer finish(g)
	init(g)
	count: Frame_Count
	r := cm.Renderer {
		data      = &count,
		clear     = proc(data: rawptr, c: cm.Color) {(^Frame_Count)(data).clears += 1},
		fill_rect = proc(data: rawptr, x, y, w, h: int, c: cm.Color) {(^Frame_Count)(data).fills += 1},
		present   = proc(data: rawptr) {(^Frame_Count)(data).presents += 1},
	}
	draw(g, &r) // title
	handle_command(g, .Green)
	draw(g, &r) // playing
	update(g, 31_000)
	draw(g, &r) // game over
	g.error = "BROKEN"
	draw(g, &r) // the error screen
	testing.expect_value(t, count.presents, 4)
	testing.expect_value(t, count.clears, 4)
}

@(test)
test_the_world_has_the_helpers_things_and_sound_the_incremental_game_needs :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	helpers, things, placed := 0, 0, 0
	for ci in 0 ..< rt.character_count(g.world) {
		if ct := rt.character_type(g.world, ci); ct != nil && cm.name_str(&ct.name) == "helper" {
			helpers += 1
			testing.expect(t, !rt.play_position(&g.play, ci).placed) // they stand nowhere until bought
		}
		if rt.character_has_tag(g.world, ci, g.thing_tag) {
			things += 1
			if rt.play_position(&g.play, ci).placed {
				placed += 1
			}
		}
	}
	testing.expect_value(t, helpers, 4)
	testing.expect_value(t, things, 4)
	testing.expect_value(t, placed, 1) // only the first Thing is in the room at the start
	_, has_buy := rt.find_sound(g.world, "buy")
	testing.expect(t, has_buy)
}
