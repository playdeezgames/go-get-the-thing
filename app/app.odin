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
		default_file = game.SAVE_FILE,
		take_save = proc(data: rawptr) -> (string, bool) {
			// The web frontend downloads a file on every save, which no autosave should do: web saving
			// waits for the Anvil's silent-save story (USER_STORIES.md, 13). Native saves as normal.
			when ODIN_ARCH == .wasm32 {
				return "", false
			} else {
				return game.take_save((^game.Game)(data))
			}
		},
		saved = proc(data: rawptr) {},
		wants_load = proc(data: rawptr) -> bool {return game.wants_load((^game.Game)(data))},
		load = proc(data: rawptr, bytes: []u8) -> bool {return game.load_save((^game.Game)(data), bytes)},
		set_input_map = proc(data: rawptr, m: ^cm.Input_Map) {(^game.Game)(data).input_map = m},
		handle_event = proc(data: rawptr, ev: cm.Input_Event) {
			g := (^game.Game)(data)
			if cmd, ok := ev.(cm.Command); ok {
				game.handle_command(g, cmd.action)
			} else {
				game.handle_mouse(g, ev)
			}
		},
		update = proc(data: rawptr, dt_ms: f64) {game.update((^game.Game)(data), dt_ms)},
		take_audio = proc(data: rawptr) -> (cm.Audio_Request, bool) {return game.take_audio((^game.Game)(data))},
		draw = proc(data: rawptr, r: ^cm.Renderer) {game.draw((^game.Game)(data), r)},
	}
}
