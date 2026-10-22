#+build !js
package game

import cm "anvil:common"
import "core:testing"

@(test)
test_the_hud_sits_in_the_strip_beside_the_pad_and_fits_its_boxes :: proc(t: ^testing.T) {
	// the boxes are left and right of the pad buttons and inside the strip
	first, last := PAD_BUTTONS[0].rect, PAD_BUTTONS[4].rect
	testing.expect(t, HUD_LEFT.x + HUD_LEFT.w <= first.x)
	testing.expect(t, HUD_RIGHT.x >= last.x + last.w)
	testing.expect(t, HUD_RIGHT.x + HUD_RIGHT.w <= cm.SCREEN_W)
	for box in ([2]cm.Rect{HUD_LEFT, HUD_RIGHT}) {
		testing.expect(t, box.y >= PAD_STRIP.y && box.y + box.h <= PAD_STRIP.y + PAD_STRIP.h)
		testing.expect(t, HUD_TOP_Y >= box.y && HUD_BOTTOM_Y + cm.GLYPH_H <= box.y + box.h)
	}
	// even a long game's numbers fit
	g := new(Game)
	defer free(g)
	g.score = 99_999
	g.ms_left = 999_000
	score_label, score_value, time_label, time_value := hud_text(g)
	for s in ([4]string{score_label, score_value, time_label, time_value}) {
		testing.expect(t, cm.text_is_drawable(s))
		testing.expect(t, cm.text_width(s) <= HUD_LEFT.w - 4)
		testing.expect(t, cm.text_width(s) <= HUD_RIGHT.w - 4)
	}
}

@(test)
test_the_clock_turns_red_in_the_last_seconds_of_a_round :: proc(t: ^testing.T) {
	g := started()
	defer finish(g)
	testing.expect(t, time_colour(g) != HUD_ALERT)
	update(g, 25_500)
	testing.expect_value(t, time_colour(g), HUD_ALERT)
	update(g, 10_000) // over: back to plain
	testing.expect(t, time_colour(g) != HUD_ALERT)
}
