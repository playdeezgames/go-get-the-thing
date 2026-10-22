// Score and time, in the strip below the room on either side of the pad: a small label over a value.
package game

import cm "anvil:common"
import "core:fmt"

HUD_LEFT :: cm.Rect{0, 160, 52, 20}
HUD_RIGHT :: cm.Rect{268, 160, 52, 20}
HUD_TOP_Y :: 163 // the label row
HUD_BOTTOM_Y :: 171 // the value row
HUD_LABEL :: cm.Color{170, 170, 170}
HUD_INK :: cm.Color{255, 255, 255}
HUD_ALERT :: cm.Color{255, 85, 85}
HUD_ALERT_MS :: 5000.0

// Two label/value pairs. In a run: the coins earned so far and the clock. Otherwise: the coins you
// have and your best run. (On the temp allocator.)
hud_text :: proc(g: ^Game) -> (left_label, left_value, right_label, right_value: string) {
	if g.state == .Playing {
		return "COINS", fmt.tprintf("%d", g.score), "TIME", fmt.tprintf("%d", seconds_left(g))
	}
	return "COINS", fmt.tprintf("%d", g.progress.coins), "BEST", fmt.tprintf("%d", g.progress.best_run)
}

// The clock is red for the last seconds of a round being played.
time_colour :: proc(g: ^Game) -> cm.Color {
	return g.state == .Playing && g.ms_left <= HUD_ALERT_MS ? HUD_ALERT : HUD_INK
}

draw_hud :: proc(g: ^Game, r: ^cm.Renderer) {
	left_label, left_value, right_label, right_value := hud_text(g)
	centred(r, HUD_LEFT, HUD_TOP_Y, left_label, HUD_LABEL)
	centred(r, HUD_LEFT, HUD_BOTTOM_Y, left_value, HUD_INK)
	centred(r, HUD_RIGHT, HUD_TOP_Y, right_label, HUD_LABEL)
	centred(r, HUD_RIGHT, HUD_BOTTOM_Y, right_value, time_colour(g))
}

centred :: proc(r: ^cm.Renderer, box: cm.Rect, y: int, text: string, c: cm.Color) {
	cm.draw_text(r, box.x + (box.w - cm.text_width(text)) / 2, y, text, c)
}
