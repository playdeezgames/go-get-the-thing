#+build !js
package game

import cm "anvil:common"
import rt "anvil:anvil_runtime"
import "core:testing"

click :: proc(g: ^Game, x, y: int, down: bool) {
	handle_mouse(g, cm.Mouse_Button_Event{button = .Left, x = x, y = y, down = down})
}

centre :: proc(b: Pad_Button) -> (int, int) {
	return b.rect.x + b.rect.w / 2, b.rect.y + b.rect.h / 2
}

@(test)
test_the_on_screen_pad_fits_below_the_room_and_its_buttons_do_not_overlap :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	cols, rows, _ := rt.map_size(g.world, g.map_index)
	_, th := rt.tile_size(g.world)
	testing.expect(t, rows * th <= PAD_STRIP.y) // the room is above the strip
	_ = cols
	for a, i in PAD_BUTTONS {
		r := a.rect
		testing.expect(t, r.x >= 0 && r.x + r.w <= cm.SCREEN_W && r.y >= PAD_STRIP.y && r.y + r.h <= cm.SCREEN_H)
		for b, j in PAD_BUTTONS {
			if i != j {
				overlap := a.rect.x < b.rect.x + b.rect.w && b.rect.x < a.rect.x + a.rect.w && a.rect.y < b.rect.y + b.rect.h && b.rect.y < a.rect.y + a.rect.h
				testing.expect(t, !overlap)
			}
		}
	}
	// each of the five commands is on the pad once
	seen: [cm.Action]int
	for b in PAD_BUTTONS {
		seen[b.action] += 1
	}
	for a in ([?]cm.Action{.Up, .Down, .Left, .Right, .Green}) {
		testing.expect_value(t, seen[a], 1)
	}
	// the widest label the input map allows still fits the green button
	for b in PAD_BUTTONS {
		if b.action == .Green {
			testing.expect(t, cm.text_width("WWWWWWWWWWWW") <= b.rect.w - 4)
		}
	}
}

@(test)
test_clicking_a_pad_button_sends_its_command :: proc(t: ^testing.T) {
	g := new(Game)
	defer finish(g)
	init(g)
	set_seed(g, 1)
	for b in PAD_BUTTONS {
		x, y := centre(b)
		a, ok := pad_button_at(x, y)
		testing.expect(t, ok)
		testing.expect_value(t, a, b.action)
	}
	_, ok := pad_button_at(5, 5) // the room is not a button
	testing.expect(t, !ok)
	gx, gy := centre(PAD_BUTTONS[len(PAD_BUTTONS) - 1])
	for b in PAD_BUTTONS {
		if b.action == .Green {
			gx, gy = centre(b)
		}
	}
	click(g, gx, gy, true)
	click(g, gx, gy, false)
	testing.expect_value(t, g.state, State.Playing)
	for b in PAD_BUTTONS {
		if b.action == .Right {
			x, y := centre(b)
			click(g, x, y, true)
			click(g, x, y, false)
		}
	}
	testing.expect_value(t, player_at(g), [2]int{3, 5})
}

@(test)
test_holding_a_pad_button_repeats_after_a_delay_and_release_stops_it :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	bx, by: int
	for b in PAD_BUTTONS {
		if b.action == .Right {
			bx, by = centre(b)
		}
	}
	click(g, bx, by, true)
	testing.expect_value(t, player_at(g), [2]int{3, 5}) // at once
	update(g, PAD_REPEAT_DELAY_MS - 1)
	testing.expect_value(t, player_at(g), [2]int{3, 5}) // not yet
	update(g, 2)
	testing.expect_value(t, player_at(g), [2]int{4, 5}) // first repeat
	update(g, PAD_REPEAT_MS)
	testing.expect_value(t, player_at(g), [2]int{5, 5})
	click(g, bx, by, false)
	update(g, 1000)
	testing.expect_value(t, player_at(g), [2]int{5, 5}) // released
}

@(test)
test_sliding_off_a_button_releases_it :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	bx, by: int
	for b in PAD_BUTTONS {
		if b.action == .Right {
			bx, by = centre(b)
		}
	}
	click(g, bx, by, true)
	handle_mouse(g, cm.Mouse_Move{x = 5, y = 5})
	update(g, 1000)
	testing.expect_value(t, player_at(g), [2]int{3, 5})
}

@(test)
test_other_mouse_buttons_and_clicks_in_the_room_do_nothing :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	bx, by: int
	for b in PAD_BUTTONS {
		if b.action == .Right {
			bx, by = centre(b)
		}
	}
	handle_mouse(g, cm.Mouse_Button_Event{button = .Right, x = bx, y = by, down = true})
	click(g, 100, 100, true)
	update(g, 1000)
	testing.expect_value(t, player_at(g), [2]int{2, 5})
}
