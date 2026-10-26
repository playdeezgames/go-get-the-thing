// The save file: what is kept between runs, as JSON. Strict on the way in (a bad file is refused and
// changes nothing) and plain on the way out.
package game

import "core:encoding/json"
import "core:fmt"
import "core:strings"

SAVE_FILE :: "go-get-the-thing-save.json" // unique: every itch.io HTML5 game shares one browser storage origin
SAVE_VERSION :: 3 // 1 (no prestige fields) and 2 (no switches) still load
MAX_SAVED_NUMBER :: 1_000_000_000 // well beyond play, and it fits the 32-bit int of the web build

// The save text, on the temp allocator.
progress_to_json :: proc(p: Progress) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(
		&b,
		`{{"version": %d, "coins": %d, "best_run": %d, "era_earned": %d, "gems": %d, "prestiges": %d, "levels": {{`,
		SAVE_VERSION, p.coins, p.best_run, p.era_earned, p.gems, p.prestiges,
	)
	first := true
	for u in Upgrade {
		fmt.sbprintf(&b, `%s"%s": %d`, first ? "" : ", ", UPGRADES[u].key, p.levels[u])
		first = false
	}
	strings.write_string(&b, `}, "perks": {`)
	first = true
	for k in Perk {
		fmt.sbprintf(&b, `%s"%s": %d`, first ? "" : ", ", PERKS[k].key, p.perks[k])
		first = false
	}
	strings.write_string(&b, `}, "auto_off": {`)
	first = true
	for t in Toggle {
		fmt.sbprintf(&b, `%s"%s": %d`, first ? "" : ", ", TOGGLE_KEYS[t], p.auto_off[t] ? 1 : 0)
		first = false
	}
	strings.write_string(&b, "}}\n")
	return strings.to_string(b)
}

// The progress in a save file, or ok = false for anything that is not a valid one.
progress_from_json :: proc(bytes: []u8) -> (p: Progress, ok: bool) {
	value, err := json.parse(bytes, .JSON, true, context.temp_allocator)
	if err != .None {
		return {}, false
	}
	obj, is_obj := value.(json.Object)
	if !is_obj {
		return {}, false
	}
	if v, found := whole_number(obj, "version", SAVE_VERSION); !found || v < 1 {
		return {}, false
	}
	coins, coins_ok := whole_number(obj, "coins", MAX_SAVED_NUMBER)
	best, best_ok := whole_number(obj, "best_run", MAX_SAVED_NUMBER)
	if !coins_ok || !best_ok {
		return {}, false
	}
	p.coins, p.best_run = coins, best
	era, era_ok := optional_number(obj, "era_earned", MAX_SAVED_NUMBER)
	gems, gems_ok := optional_number(obj, "gems", MAX_SAVED_NUMBER)
	prestiges, prestiges_ok := optional_number(obj, "prestiges", MAX_SAVED_NUMBER)
	if !era_ok || !gems_ok || !prestiges_ok {
		return {}, false
	}
	p.era_earned, p.gems, p.prestiges = era, gems, prestiges
	if lv, present := obj["levels"]; present {
		levels, is_levels := lv.(json.Object)
		if !is_levels {
			return {}, false
		}
		for key in levels {
			u, known := upgrade_for_key(key)
			if !known {
				return {}, false
			}
			level, level_ok := whole_number(levels, key, UPGRADES[u].max_level)
			if !level_ok {
				return {}, false
			}
			p.levels[u] = level
		}
	}
	if pv, present := obj["perks"]; present {
		perks, is_perks := pv.(json.Object)
		if !is_perks {
			return {}, false
		}
		for key in perks {
			k, known := perk_for_key(key)
			if !known {
				return {}, false
			}
			level, level_ok := whole_number(perks, key, PERKS[k].max_level)
			if !level_ok {
				return {}, false
			}
			p.perks[k] = level
		}
	}
	if av, present := obj["auto_off"]; present {
		switches, is_obj := av.(json.Object)
		if !is_obj {
			return {}, false
		}
		for key in switches {
			t, known := toggle_for_key(key)
			if !known {
				return {}, false
			}
			off, off_ok := whole_number(switches, key, 1)
			if !off_ok {
				return {}, false
			}
			p.auto_off[t] = off == 1
		}
	}
	return p, true
}

toggle_for_key :: proc(key: string) -> (Toggle, bool) {
	for t in Toggle {
		if TOGGLE_KEYS[t] == key {
			return t, true
		}
	}
	return {}, false
}

// Like `whole_number`, but a member that is not there is 0 (an older save).
optional_number :: proc(obj: json.Object, key: string, max: int) -> (n: int, ok: bool) {
	if _, present := obj[key]; !present {
		return 0, true
	}
	return whole_number(obj, key, max)
}

// An integer member of an object in 0..=max (a float, a string or a negative is not one).
whole_number :: proc(obj: json.Object, key: string, max: int) -> (n: int, ok: bool) {
	value, present := obj[key]
	if !present {
		return 0, false
	}
	i, is_int := value.(json.Integer)
	if !is_int || i < 0 || i > i64(max) {
		return 0, false
	}
	return int(i), true
}

upgrade_for_key :: proc(key: string) -> (Upgrade, bool) {
	for u in Upgrade {
		if UPGRADES[u].key == key {
			return u, true
		}
	}
	return {}, false
}

perk_for_key :: proc(key: string) -> (Perk, bool) {
	for k in Perk {
		if PERKS[k].key == key {
			return k, true
		}
	}
	return {}, false
}
