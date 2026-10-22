// The upgrades coins buy between runs: what they are, what they cost, and what they change. Pure
// numbers, no screens: the shop UI and the run use these.
package game

import "core:math"

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

// Perks are bought with gems, the prestige currency, and last through prestiges.
Perk :: enum {
	Time_Chance,
}

Perk_Info :: struct {
	key:        string,
	name:       string,
	what:       string,
	base_cost:  int, // in gems
	growth_pct: int,
	max_level:  int,
}

PERKS := [Perk]Perk_Info {
	.Time_Chance = {"time_chance", "TIME BONUS CHANCE", "+5% CHANCE A THING ADDS 5 SECONDS", 2, 150, 10},
}

TIME_CHANCE_PCT_PER_LEVEL :: 5
TIME_BONUS_MS :: 5000
// Helpers pick up Things many times a second late in the game: without a limit a small chance of
// extra time would outrun the clock and a run would never end.
MAX_TIME_BONUSES_PER_RUN :: 10
GEM_ERA_DIVISOR :: 1000 // gems = the square root of (coins earned since the last prestige / this)

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
	era_earned: int, // the coins earned since the last prestige (what the next prestige is worth)
	gems:     int, // the prestige currency, spent on perks
	prestiges: int, // how many times the player has prestiged
	perks:    [Perk]int,
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

// --- gems and perks ----------------------------------------------------------------------------

perk_cost :: proc(k: Perk, level: int) -> int {
	info := PERKS[k]
	cost := info.base_cost
	for _ in 0 ..< level {
		cost = cost * info.growth_pct / 100 + 1
	}
	return cost
}

// The gem price of the next level of a perk, or 0 when it is at its maximum.
next_perk_cost :: proc(p: Progress, k: Perk) -> int {
	return p.perks[k] >= PERKS[k].max_level ? 0 : perk_cost(k, p.perks[k])
}

// Buys one level of a perk with gems (.Too_Poor means too few gems). A refusal changes nothing.
buy_perk :: proc(p: ^Progress, k: Perk) -> Buy_Result {
	level := p.perks[k]
	if level >= PERKS[k].max_level {
		return .Max_Level
	}
	cost := perk_cost(k, level)
	if p.gems < cost {
		return .Too_Poor
	}
	p.gems -= cost
	p.perks[k] = level + 1
	return .Bought
}

// The chance, in percent, that a picked-up Thing adds time to the clock.
time_chance_pct :: proc(p: Progress) -> int {
	return p.perks[.Time_Chance] * TIME_CHANCE_PCT_PER_LEVEL
}

// What prestiging now would give: the square root of the coins earned since the last prestige,
// scaled down by GEM_ERA_DIVISOR and rounded down.
gems_for_prestige :: proc(era_earned: int) -> int {
	n := era_earned / GEM_ERA_DIVISOR
	r := int(math.sqrt(f64(n)))
	for r * r > n {
		r -= 1
	}
	for (r + 1) * (r + 1) <= n {
		r += 1
	}
	return r
}

// Prestige: trade everything but the perks for gems. Coins, upgrade levels and the era's earnings
// reset; gems, perks, the best run and the prestige count stay. Returns the gems gained, and does
// nothing (0) if the era has not earned enough for one.
prestige :: proc(p: ^Progress) -> int {
	gained := gems_for_prestige(p.era_earned)
	if gained == 0 {
		return 0
	}
	p.gems = min(p.gems + gained, MAX_SAVED_NUMBER)
	p.prestiges += 1
	p.coins = 0
	p.era_earned = 0
	p.levels = {}
	return gained
}
