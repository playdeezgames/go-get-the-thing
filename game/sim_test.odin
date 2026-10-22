#+build !js
package game

// A balance simulation, not a unit test: bots play many whole runs, buying upgrades greedily, and
// the numbers are printed. It does nothing unless asked for:
//   ./build.sh test -define:SIM=true -define:ODIN_TEST_NAMES=game.test_balance_report
import cm "anvil:common"
import "core:fmt"
import "core:testing"

SIM :: #config(SIM, false)
SIM_FRAME_MS :: 16.0
SIM_MAX_RUNS :: 600

Sim_Run :: struct {
	earned:    int,
	run_s:     f64,
	coins_after_shop: int,
	bought:    [dynamic]Upgrade,
	levels:    [Upgrade]int,
}

Sim :: struct {
	runs:        [dynamic]Sim_Run,
	first_buy:   [Upgrade]int, // the run (1-based) after which the first level was bought, 0 = never
	maxed_at:    [Upgrade]int,
	all_maxed_at: int,
	total_game_s: f64,
}

// Plays runs until everything is maxed (or SIM_MAX_RUNS). In runs up to `plays_until_run` the player is
// a bot that walks to the nearest Thing as fast as the player-speed upgrade allows; after that the
// player stands still and only helpers earn.
simulate :: proc(seed: u64, plays_until_run: int) -> Sim {
	g := new(Game)
	defer {destroy(g); free(g)}
	init(g)
	set_seed(g, seed)
	handle_command(g, .Green) // the title -> the shop
	sim: Sim
	for run in 1 ..= SIM_MAX_RUNS {
		start_run(g)
		run_s := g.ms_left / 1000
		for g.state == .Playing {
			if run <= plays_until_run && g.step_cooldown_ms <= 0 {
				if dx, dy, ok := step_towards_nearest_thing(g, g.player); ok {
					handle_command(g, dx > 0 ? .Right : dx < 0 ? .Left : dy > 0 ? .Down : .Up)
				}
			}
			update(g, SIM_FRAME_MS)
			free_all(context.temp_allocator)
		}
		r := Sim_Run{earned = g.last_run, run_s = run_s}
		// shopping: always the cheapest upgrade that is not maxed, while it can be paid
		for {
			cheapest, found := Upgrade.Thing_Value, false
			for u in Upgrade {
				if g.progress.levels[u] < UPGRADES[u].max_level && (!found || next_cost(g.progress, u) < next_cost(g.progress, cheapest)) {
					cheapest, found = u, true
				}
			}
			if !found || buy(&g.progress, cheapest) != .Bought {
				break
			}
			append(&r.bought, cheapest)
			if sim.first_buy[cheapest] == 0 {
				sim.first_buy[cheapest] = run
			}
			if g.progress.levels[cheapest] == UPGRADES[cheapest].max_level {
				sim.maxed_at[cheapest] = run
			}
		}
		r.coins_after_shop = g.progress.coins
		r.levels = g.progress.levels
		append(&sim.runs, r)
		sim.total_game_s += run_s
		done := true
		for u in Upgrade {
			done &&= g.progress.levels[u] >= UPGRADES[u].max_level
		}
		if done {
			sim.all_maxed_at = run
			break
		}
	}
	return sim
}

report :: proc(title: string, sim: Sim, table: bool) {
	fmt.printfln("\n=== %s ===", title)
	if table {
		fmt.println("run  earned  secs  bought this shop (levels after: TV RL HP HS MT PS)")
		for r, i in sim.runs {
			if i < 12 || i % 10 == 0 || i == len(sim.runs) - 1 {
				names := ""
				for b in r.bought {
					names = fmt.tprintf("%s %s", names, UPGRADES[b].name)
				}
				fmt.printfln(
					"%3d  %6d  %4.0f  [%d %d %d %d %d %d]%s",
					i + 1, r.earned, r.run_s,
					r.levels[.Thing_Value], r.levels[.Run_Length], r.levels[.Helpers], r.levels[.Helper_Speed], r.levels[.More_Things], r.levels[.Player_Speed],
					names,
				)
			}
		}
	}
	defer {
		for r in sim.runs {
			delete(r.bought)
		}
		delete(sim.runs)
	}
	first, last := sim.runs[0], sim.runs[len(sim.runs) - 1]
	fmt.printfln("first run earned %d, last run earned %d (%.1fx)", first.earned, last.earned, f64(last.earned) / f64(max(first.earned, 1)))
	if sim.all_maxed_at > 0 {
		fmt.printfln("everything maxed after run %d = %.1f minutes of play", sim.all_maxed_at, sim.total_game_s / 60)
	} else {
		fmt.printfln("NOT everything maxed after %d runs (%.1f minutes)", len(sim.runs), sim.total_game_s / 60)
	}
	for u in Upgrade {
		fmt.printfln("  %-13s first bought in run %3d, maxed in run %3d", UPGRADES[u].name, sim.first_buy[u], sim.maxed_at[u])
	}
}

@(test)
test_balance_report :: proc(t: ^testing.T) {
	when !SIM {
		return
	}
	total_cost := 0
	for u in Upgrade {
		for level in 0 ..< UPGRADES[u].max_level {
			total_cost += upgrade_cost(u, level)
		}
	}
	fmt.printfln("\nPrice of every upgrade level together: %d coins", total_cost)
	for u in Upgrade {
		sum := 0
		for level in 0 ..< UPGRADES[u].max_level {
			sum += upgrade_cost(u, level)
		}
		fmt.printfln("  %-13s %7d  (level 1 costs %d, last costs %d)", UPGRADES[u].name, sum, upgrade_cost(u, 0), upgrade_cost(u, UPGRADES[u].max_level - 1))
	}
	report("player plays every run, helpers help", simulate(1, SIM_MAX_RUNS), true)
	report("player plays 10 runs, then goes AFK (helpers only)", simulate(1, 10), true)
	report("player plays 8 runs, then goes AFK (helpers only)", simulate(1, 8), false)
	for seed in 2 ..= 3 {
		report(fmt.aprintf("player plays every run, seed %d", seed), simulate(u64(seed), SIM_MAX_RUNS), false)
	}
	_ = cm.SCREEN_W
}
