#+build !js
package game

import "core:strings"
import "core:testing"

@(test)
test_progress_survives_a_save_and_load :: proc(t: ^testing.T) {
	p := Progress{coins = 1234, best_run = 56}
	p.levels[.Thing_Value], p.levels[.Helpers], p.levels[.Player_Speed] = 3, 2, 8
	text := progress_to_json(p)
	back, ok := progress_from_json(transmute([]u8)text)
	testing.expect(t, ok)
	testing.expect_value(t, back, p)
}

@(test)
test_a_new_player_saves_and_loads_a_blank_progress :: proc(t: ^testing.T) {
	text := progress_to_json({})
	back, ok := progress_from_json(transmute([]u8)text)
	testing.expect(t, ok)
	testing.expect_value(t, back, Progress{})
}

@(test)
test_a_bad_save_is_refused :: proc(t: ^testing.T) {
	bad := []string {
		``,
		`not json`,
		`[]`,
		`{"coins": 1}`, // no version
		`{"version": 2, "coins": 1, "best_run": 0, "levels": {}}`,
		`{"version": 1, "coins": -1, "best_run": 0, "levels": {}}`,
		`{"version": 1, "coins": 1.5, "best_run": 0, "levels": {}}`,
		`{"version": 1, "coins": "5", "best_run": 0, "levels": {}}`,
		`{"version": 1, "coins": 1000000000000000, "best_run": 0, "levels": {}}`,
		`{"version": 1, "coins": 1, "best_run": -3, "levels": {}}`,
		`{"version": 1, "coins": 1, "best_run": 0, "levels": {"thing_value": 99}}`,
		`{"version": 1, "coins": 1, "best_run": 0, "levels": {"thing_value": -1}}`,
		`{"version": 1, "coins": 1, "best_run": 0, "levels": {"made_up": 1}}`,
		`{"version": 1, "coins": 1, "best_run": 0, "levels": 7}`,
	}
	for s in bad {
		_, ok := progress_from_json(transmute([]u8)s)
		testing.expectf(t, !ok, "accepted: %s", s)
	}
}

@(test)
test_a_save_may_leave_out_levels_that_are_zero :: proc(t: ^testing.T) {
	p, ok := progress_from_json(transmute([]u8)string(`{"version": 1, "coins": 7, "best_run": 2, "levels": {"helpers": 1}}`))
	testing.expect(t, ok)
	testing.expect_value(t, p.coins, 7)
	testing.expect_value(t, p.levels[.Helpers], 1)
	testing.expect_value(t, p.levels[.Thing_Value], 0)
}

@(test)
test_the_tool_asks_for_the_save_once_at_start_and_saves_when_asked :: proc(t: ^testing.T) {
	g := new(Game)
	defer finish(g)
	init(g)
	testing.expect(t, wants_load(g))
	testing.expect(t, !wants_load(g)) // once
	_, wanted := take_save(g)
	testing.expect(t, !wanted) // nothing to save yet
	testing.expect(t, load_save(g, transmute([]u8)string(`{"version": 1, "coins": 42, "best_run": 9, "levels": {}}`)))
	testing.expect_value(t, g.progress.coins, 42)
	testing.expect(t, !load_save(g, transmute([]u8)string(`junk`)))
	testing.expect_value(t, g.progress.coins, 42) // a bad file changes nothing
	g.progress.coins = 50
	request_save(g)
	text, ok := take_save(g)
	testing.expect(t, ok)
	testing.expect(t, strings.contains(text, `"coins": 50`))
	_, again := take_save(g)
	testing.expect(t, !again) // one request, one save
}
