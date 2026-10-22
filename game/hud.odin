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

// "SCORE", its value, "TIME", its value (on the temp allocator).
hud_text :: proc(g: ^Game) -> (score_label, score_value, time_label, time_value: string) {
	return "SCORE", fmt.tprintf("%d", g.score), "TIME", fmt.tprintf("%d", seconds_left(g))
}

// The clock is red for the last seconds of a round being played.
time_colour :: proc(g: ^Game) -> cm.Color {
	return g.state == .Playing && g.ms_left <= HUD_ALERT_MS ? HUD_ALERT : HUD_INK
}

draw_hud :: proc(g: ^Game, r: ^cm.Renderer) {
	score_label, score_value, time_label, time_value := hud_text(g)
	centred(r, HUD_LEFT, HUD_TOP_Y, score_label, HUD_LABEL)
	centred(r, HUD_LEFT, HUD_BOTTOM_Y, score_value, HUD_INK)
	centred(r, HUD_RIGHT, HUD_TOP_Y, time_label, HUD_LABEL)
	centred(r, HUD_RIGHT, HUD_BOTTOM_Y, time_value, time_colour(g))
}

centred :: proc(r: ^cm.Renderer, box: cm.Rect, y: int, text: string, c: cm.Color) {
	cm.draw_text(r, box.x + (box.w - cm.text_width(text)) / 2, y, text, c)
}
