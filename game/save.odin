// The save file: what is kept between runs, as JSON. Strict on the way in (a bad file is refused and
// changes nothing) and plain on the way out.
package game

import "core:encoding/json"
import "core:fmt"
import "core:strings"

SAVE_FILE :: "save.json"
SAVE_VERSION :: 1
MAX_SAVED_NUMBER :: 1_000_000_000 // well beyond play, and it fits the 32-bit int of the web build

// The save text, on the temp allocator.
progress_to_json :: proc(p: Progress) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `{{"version": %d, "coins": %d, "best_run": %d, "levels": {{`, SAVE_VERSION, p.coins, p.best_run)
	first := true
	for u in Upgrade {
		fmt.sbprintf(&b, `%s"%s": %d`, first ? "" : ", ", UPGRADES[u].key, p.levels[u])
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
	if v, found := whole_number(obj, "version", SAVE_VERSION); !found || v != SAVE_VERSION {
		return {}, false
	}
	coins, coins_ok := whole_number(obj, "coins", MAX_SAVED_NUMBER)
	best, best_ok := whole_number(obj, "best_run", MAX_SAVED_NUMBER)
	if !coins_ok || !best_ok {
		return {}, false
	}
	p.coins, p.best_run = coins, best
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
	return p, true
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
