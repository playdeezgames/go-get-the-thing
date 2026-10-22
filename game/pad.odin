// The on-screen pad: a row of buttons below the room that stands in for the eight-command input when
// only a mouse (or a finger) is available. Pressing a button sends its command at once; holding a
// direction repeats it. Only the commands the game uses are here: the four directions and green.
package game

import cm "anvil:common"
import "core:fmt"

PAD_STRIP :: cm.Rect{0, 160, cm.SCREEN_W, 20} // below the 20x10 room
PAD_REPEAT_DELAY_MS :: 300.0
PAD_REPEAT_MS :: 120.0

Pad_Button :: struct {
	action: cm.Action,
	rect:   cm.Rect,
}

// Left, down, up, right, then a wide green button, centred in the strip.
PAD_BUTTONS :: [5]Pad_Button {
	{.Left, {54, 162, 28, 16}},
	{.Down, {86, 162, 28, 16}},
	{.Up, {118, 162, 28, 16}},
	{.Right, {150, 162, 28, 16}},
	{.Green, {194, 162, 72, 16}},
}

pad_button_at :: proc(x, y: int) -> (cm.Action, bool) {
	for b in PAD_BUTTONS {
		if x >= b.rect.x && x < b.rect.x + b.rect.w && y >= b.rect.y && y < b.rect.y + b.rect.h {
			return b.action, true
		}
	}
	return {}, false
}

// Mouse events (logical pixels): a left press on a button sends it and starts the repeat clock for a
// direction; releasing, or sliding off the button, stops it.
handle_mouse :: proc(g: ^Game, ev: cm.Input_Event) {
	switch e in ev {
	case cm.Mouse_Button_Event:
		if e.button != .Left {
			return
		}
		if !e.down {
			g.holding = false
			return
		}
		if a, ok := pad_button_at(e.x, e.y); ok {
			g.holding, g.held = true, a
			g.repeat_ms = PAD_REPEAT_DELAY_MS
			handle_command(g, a)
		}
	case cm.Mouse_Move:
		if g.holding {
			if a, ok := pad_button_at(e.x, e.y); !ok || a != g.held {
				g.holding = false
			}
		}
	case cm.Command, cm.Mouse_Wheel:
	}
}

// Repeats a held direction; called from `update`.
repeat_held :: proc(g: ^Game, dt_ms: f64) {
	if !g.holding || g.held == .Green || !(dt_ms > 0) {
		return
	}
	g.repeat_ms -= dt_ms
	for g.repeat_ms <= 0 && g.holding {
		handle_command(g, g.held)
		g.repeat_ms += PAD_REPEAT_MS
	}
}

draw_pad :: proc(g: ^Game, r: ^cm.Renderer) {
	for b in PAD_BUTTONS {
		pressed := g.holding && g.held == b.action
		face := pressed ? cm.Color{150, 150, 150} : cm.Color{60, 60, 60}
		ink := pressed ? cm.Color{0, 0, 0} : cm.Color{255, 255, 255}
		rc := b.rect
		cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, cm.Color{200, 200, 200})
		cm.renderer_fill_rect(r, rc.x + 1, rc.y + 1, rc.w - 2, rc.h - 2, face)
		if b.action == .Green {
			label := cm.action_label(g.input_map, .Green)
			cm.draw_text(r, rc.x + (rc.w - cm.text_width(label)) / 2, rc.y + (rc.h - cm.GLYPH_H) / 2, label, ink)
		} else {
			draw_arrow(r, rc, b.action, ink)
		}
	}
}

// A small triangle pointing the way, built from rows of rectangles.
draw_arrow :: proc(r: ^cm.Renderer, rc: cm.Rect, a: cm.Action, c: cm.Color) {
	cx, cy := rc.x + rc.w / 2, rc.y + rc.h / 2
	for i in 0 ..< 5 {
		half := i // 0..4: the row grows away from the tip
		switch a {
		case .Up:
			cm.renderer_fill_rect(r, cx - half, cy - 3 + i, 2 * half + 1, 1, c)
		case .Down:
			cm.renderer_fill_rect(r, cx - half, cy + 3 - i, 2 * half + 1, 1, c)
		case .Left:
			cm.renderer_fill_rect(r, cx - 3 + i, cy - half, 1, 2 * half + 1, c)
		case .Right:
			cm.renderer_fill_rect(r, cx + 3 - i, cy - half, 1, 2 * half + 1, c)
		case .Green, .Red, .Blue, .Yellow:
		}
	}
}
