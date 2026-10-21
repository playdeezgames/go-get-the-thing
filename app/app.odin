// The game's app for the Anvil's frontends (see the Anvil's GAMES.md): `make_tool` is all they need.
package app

import game "../game"
import cm "anvil:common"
import "core:time"

g: game.Game

make_tool :: proc() -> cm.Tool {
	game.init(&g)
	game.set_seed(&g, u64(time.now()._nsec))
	return cm.Tool {
		title = "Go Get the Thing!",
		data = &g,
		set_input_map = proc(data: rawptr, m: ^cm.Input_Map) {(^game.Game)(data).input_map = m},
		handle_event = proc(data: rawptr, ev: cm.Input_Event) {
			if cmd, ok := ev.(cm.Command); ok {
				game.handle_command((^game.Game)(data), cmd.action)
			}
		},
		update = proc(data: rawptr, dt_ms: f64) {game.update((^game.Game)(data), dt_ms)},
		draw = proc(data: rawptr, r: ^cm.Renderer) {game.draw((^game.Game)(data), r)},
	}
}
