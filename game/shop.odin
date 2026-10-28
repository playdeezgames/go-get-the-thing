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
	Auto_Start, // an unlock: the START RUN row starts a run by itself
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
	.Thing_Value = {"thing_value", "THING VALUE", "+1 COIN PER THING", 8, 150, 20},
	.Run_Length = {"run_length", "RUN LENGTH", "+5 SECONDS PER RUN", 60, 210, 12},
	.Helpers = {"helpers", "HELPERS", "A HELPER COLLECTS FOR YOU", 120, 320, 4},
	.Helper_Speed = {"helper_speed", "HELPER SPEED", "HELPERS STEP FASTER", 150, 210, 8},
	.More_Things = {"more_things", "MORE THINGS", "ONE MORE THING IN THE ROOM", 400, 350, 3},
	.Player_Speed = {"player_speed", "PLAYER SPEED", "YOU STEP FASTER", 80, 200, 8},
	.Auto_Start = {"auto_start", "AUTO START", "START RUN STARTS ITSELF AFTER 15 SECONDS", 1000, 100, 1},
}

// Perks are bought with gems, the prestige currency, and last through prestiges.
Perk :: enum {
	Time_Chance,
	Lucky_Coins,
	Coin_Boost,
	Auto_Buy, // an unlock: buys a random perk after the shop sits idle
	Auto_Play, // an unlock: the player's sprite collects on its own
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
	.Lucky_Coins = {"lucky_coins", "LUCKY COINS", "+4% CHANCE A THING PAYS 5 TIMES", 3, 150, 10},
	.Coin_Boost = {"coin_boost", "COIN BOOST", "+25% COINS FROM EVERY THING", 1, 140, 10},
	.Auto_Buy = {"auto_buy", "AUTO BUY", "BUYS A RANDOM PERK AFTER 10 SECONDS IDLE", 3, 100, 1},
	.Auto_Play = {"auto_play", "AUTO PLAY", "YOUR SPRITE COLLECTS ON ITS OWN", 5, 100, 1},
}

TIME_CHANCE_PCT_PER_LEVEL :: 5
TIME_BONUS_MS :: 5000
LUCKY_CHANCE_PCT_PER_LEVEL :: 4
LUCKY_MULTIPLIER :: 5
COIN_BOOST_PCT_PER_LEVEL :: 25
// Helpers pick up Things many times a second late in the game: without a limit a small chance of
// extra time would outrun the clock and a run would never end. The limit grows with the perk's
// level, so every level of it matters.
TIME_BONUS_CAP_BASE :: 4
TIME_BONUS_CAP_PER_LEVEL :: 2
GEM_ERA_DIVISOR :: 1000 // gems = the square root of (coins earned since the last prestige / this)

// The era coins at which the player would have `gain` + 1 gems.
next_gem_at :: proc(gain: int) -> int {
	return (gain + 1) * (gain + 1) * GEM_ERA_DIVISOR
}

HELPER_BASE_STEP_MS :: 360
HELPER_STEP_GAIN_MS :: 30
PLAYER_BASE_STEP_MS :: 250
PLAYER_STEP_GAIN_MS :: 25
RUN_LENGTH_GAIN_MS :: 5000

AUTO_BUY_IDLE_MS :: 10000.0 // idle time in the shop before AUTO BUY buys
AUTO_START_MS :: 15000.0 // time on START RUN before AUTO START starts the run
AUTO_PLAY_PAUSE_MS :: 1000.0 // after the player's own input, AUTO PLAY waits this long
RESULT_AUTO_MS :: 4000.0 // with AUTO START, the result screen moves on by itself after this long

// The three automation unlocks have an on/off switch each, in the shop and in the save.
Toggle :: enum {
	Auto_Start,
	Auto_Buy,
	Auto_Play,
}

TOGGLE_KEYS := [Toggle]string {
	.Auto_Start = "auto_start",
	.Auto_Buy   = "auto_buy",
	.Auto_Play  = "auto_play",
}

// What is kept between runs: the currency, the upgrade levels and the best run.
Progress :: struct {
	coins:    int,
	best_run: int, // the most coins a single run has earned
	levels:   [Upgrade]int,
	era_earned: int, // the coins earned since the last prestige (what the next prestige is worth)
	gems:     int, // the prestige currency, spent on perks
	prestiges: int, // how many times the player has prestiged
	perks:    [Perk]int,
	auto_off: [Toggle]bool, // switched off by the player (an unlock is on until then)
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
	// rounded up, so the first boost levels are felt even when a Thing pays a single coin
	return (base * (1 + p.levels[.Thing_Value]) * (100 + COIN_BOOST_PCT_PER_LEVEL * p.perks[.Coin_Boost]) + 99) / 100
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

// The chance, in percent, that a picked-up Thing pays LUCKY_MULTIPLIER times its coins.
lucky_chance_pct :: proc(p: Progress) -> int {
	return p.perks[.Lucky_Coins] * LUCKY_CHANCE_PCT_PER_LEVEL
}

// The most time bonuses one run can have (the time-chance perk raises it).
time_bonus_cap :: proc(p: Progress) -> int {
	return TIME_BONUS_CAP_BASE + TIME_BONUS_CAP_PER_LEVEL * p.perks[.Time_Chance]
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

// --- the automation unlocks ------------------------------------------------------------------------

upgrade_toggle :: proc(u: Upgrade) -> (Toggle, bool) {
	return .Auto_Start, u == .Auto_Start
}

perk_toggle :: proc(k: Perk) -> (Toggle, bool) {
	#partial switch k {
	case .Auto_Buy:
		return .Auto_Buy, true
	case .Auto_Play:
		return .Auto_Play, true
	}
	return {}, false
}

toggle_unlocked :: proc(p: Progress, t: Toggle) -> bool {
	switch t {
	case .Auto_Start:
		return p.levels[.Auto_Start] > 0
	case .Auto_Buy:
		return p.perks[.Auto_Buy] > 0
	case .Auto_Play:
		return p.perks[.Auto_Play] > 0
	}
	return false
}

// Whether the automation is working right now: bought, and not switched off.
toggle_on :: proc(p: Progress, t: Toggle) -> bool {
	return toggle_unlocked(p, t) && !p.auto_off[t]
}

perk_affordable :: proc(p: Progress, k: Perk) -> bool {
	return p.perks[k] < PERKS[k].max_level && p.gems >= next_perk_cost(p, k)
}
