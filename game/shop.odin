// The upgrades coins buy between runs: what they are, what they cost, and what they change. Pure
// numbers, no screens: the shop UI and the run use these.
package game

Upgrade :: enum {
	Thing_Value,
	Run_Length,
	Helpers,
	Helper_Speed,
	More_Things,
	Player_Speed,
}

Upgrade_Info :: struct {
	key:        string, // in the save file
	name:       string, // in the shop (the font has capitals only)
	what:       string, // one line saying what a level does
	base_cost:  int, // the price of level 1
	growth_pct: int, // each level costs this percent of the one before, plus 1
	max_level:  int,
}

UPGRADES := [Upgrade]Upgrade_Info {
	.Thing_Value = {"thing_value", "THING VALUE", "+1 COIN PER THING", 12, 160, 20},
	.Run_Length = {"run_length", "RUN LENGTH", "+5 SECONDS PER RUN", 60, 210, 12},
	.Helpers = {"helpers", "HELPERS", "A HELPER COLLECTS FOR YOU", 250, 320, 4},
	.Helper_Speed = {"helper_speed", "HELPER SPEED", "HELPERS STEP FASTER", 150, 210, 8},
	.More_Things = {"more_things", "MORE THINGS", "ONE MORE THING IN THE ROOM", 400, 350, 3},
	.Player_Speed = {"player_speed", "PLAYER SPEED", "YOU STEP FASTER", 80, 200, 8},
}

HELPER_BASE_STEP_MS :: 600
HELPER_STEP_GAIN_MS :: 60
PLAYER_BASE_STEP_MS :: 250
PLAYER_STEP_GAIN_MS :: 25
RUN_LENGTH_GAIN_MS :: 5000

// What is kept between runs: the currency, the upgrade levels and the best run.
Progress :: struct {
	coins:    int,
	best_run: int, // the most coins a single run has earned
	levels:   [Upgrade]int,
}

Buy_Result :: enum {
	Bought,
	Max_Level,
	Too_Poor,
}

// The price of the next level of an upgrade when `level` have been bought.
upgrade_cost :: proc(u: Upgrade, level: int) -> int {
	info := UPGRADES[u]
	cost := info.base_cost
	for _ in 0 ..< level {
		cost = cost * info.growth_pct / 100 + 1
	}
	return cost
}

// The price of the next level, or 0 when the upgrade is at its maximum.
next_cost :: proc(p: Progress, u: Upgrade) -> int {
	return p.levels[u] >= UPGRADES[u].max_level ? 0 : upgrade_cost(u, p.levels[u])
}

// Buys one level. A refusal changes nothing.
buy :: proc(p: ^Progress, u: Upgrade) -> Buy_Result {
	level := p.levels[u]
	if level >= UPGRADES[u].max_level {
		return .Max_Level
	}
	cost := upgrade_cost(u, level)
	if p.coins < cost {
		return .Too_Poor
	}
	p.coins -= cost
	p.levels[u] = level + 1
	return .Bought
}

// --- what the levels do ------------------------------------------------------------------------

coins_per_thing :: proc(p: Progress, base: int) -> int {
	return base * (1 + p.levels[.Thing_Value])
}

run_ms :: proc(p: Progress, base_ms: f64) -> f64 {
	return base_ms + f64(p.levels[.Run_Length] * RUN_LENGTH_GAIN_MS)
}

helper_count :: proc(p: Progress) -> int {
	return p.levels[.Helpers]
}

// How long a helper waits between steps.
helper_step_ms :: proc(p: Progress) -> f64 {
	return f64(HELPER_BASE_STEP_MS - HELPER_STEP_GAIN_MS * p.levels[.Helper_Speed])
}

thing_count :: proc(p: Progress) -> int {
	return 1 + p.levels[.More_Things]
}

// The shortest time between two steps of the player.
player_step_ms :: proc(p: Progress) -> f64 {
	return f64(PLAYER_BASE_STEP_MS - PLAYER_STEP_GAIN_MS * p.levels[.Player_Speed])
}
