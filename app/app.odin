// The game's app for the Anvil's frontends (see the Anvil's GAMES.md): `make_tool` is all they need.
package app

import game "../game"
import cm "anvil:common"

g: game.Game

make_tool :: proc() -> cm.Tool {
	game.init(&g)
	return cm.Tool {
		title = "Go Get the Thing!",
		data = &g,
		handle_event = proc(data: rawptr, ev: cm.Input_Event) {},
		draw = proc(data: rawptr, r: ^cm.Renderer) {game.draw((^game.Game)(data), r)},
	}
}
