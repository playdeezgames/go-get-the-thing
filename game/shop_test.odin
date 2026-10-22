#+build !js
package game

import cm "anvil:common"
import "core:testing"

@(test)
test_an_upgrade_costs_its_base_at_level_zero_and_more_each_level :: proc(t: ^testing.T) {
	testing.expect_value(t, upgrade_cost(.Thing_Value, 0), 12)
	testing.expect_value(t, upgrade_cost(.Thing_Value, 1), 20) // 12 * 160% + 1
	testing.expect_value(t, upgrade_cost(.Thing_Value, 2), 33)
	for u in Upgrade {
		testing.expect_value(t, upgrade_cost(u, 0), UPGRADES[u].base_cost)
		for level in 1 ..< UPGRADES[u].max_level {
			testing.expect(t, upgrade_cost(u, level) > upgrade_cost(u, level - 1))
		}
	}
}

@(test)
test_buying_spends_coins_and_raises_the_level :: proc(t: ^testing.T) {
	p := Progress{coins = 40}
	testing.expect_value(t, buy(&p, .Thing_Value), Buy_Result.Bought) // 12
	testing.expect_value(t, p.coins, 28)
	testing.expect_value(t, p.levels[.Thing_Value], 1)
	testing.expect_value(t, buy(&p, .Thing_Value), Buy_Result.Bought) // 20 of the 28
	testing.expect_value(t, p.coins, 8)
	testing.expect_value(t, buy(&p, .Thing_Value), Buy_Result.Too_Poor) // 33
	testing.expect_value(t, p.coins, 8) // a refusal changes nothing
	testing.expect_value(t, p.levels[.Thing_Value], 2)
}

@(test)
test_an_upgrade_stops_at_its_maximum_level :: proc(t: ^testing.T) {
	for u in Upgrade {
		p := Progress{coins = 1_000_000_000}
		for _ in 0 ..< UPGRADES[u].max_level {
			testing.expect_value(t, buy(&p, u), Buy_Result.Bought)
		}
		before := p
		testing.expect_value(t, buy(&p, u), Buy_Result.Max_Level)
		testing.expect_value(t, p, before)
	}
}

@(test)
test_effects_follow_the_levels :: proc(t: ^testing.T) {
	p: Progress
	testing.expect_value(t, coins_per_thing(p, 1), 1)
	testing.expect_value(t, run_ms(p, 30_000), f64(30_000))
	testing.expect_value(t, helper_count(p), 0)
	testing.expect_value(t, helper_step_ms(p), f64(600))
	testing.expect_value(t, thing_count(p), 1)
	testing.expect_value(t, player_step_ms(p), f64(250))
	p.levels = {.Thing_Value = 3, .Run_Length = 2, .Helpers = 4, .Helper_Speed = 8, .More_Things = 3, .Player_Speed = 8}
	testing.expect_value(t, coins_per_thing(p, 1), 4)
	testing.expect_value(t, coins_per_thing(p, 2), 8)
	testing.expect_value(t, run_ms(p, 30_000), f64(40_000))
	testing.expect_value(t, helper_count(p), 4)
	testing.expect_value(t, helper_step_ms(p), f64(120))
	testing.expect_value(t, thing_count(p), 4)
	testing.expect_value(t, player_step_ms(p), f64(50))
}

@(test)
test_the_most_a_player_can_buy_fits_what_the_world_provides :: proc(t: ^testing.T) {
	// the world has 4 helpers and 4 Things (see the world test)
	testing.expect_value(t, UPGRADES[.Helpers].max_level, 4)
	testing.expect_value(t, 1 + UPGRADES[.More_Things].max_level, 4)
}

@(test)
test_upgrade_names_can_be_drawn_and_fit_the_shop :: proc(t: ^testing.T) {
	for u in Upgrade {
		testing.expect(t, cm.text_is_drawable(UPGRADES[u].name))
		testing.expect(t, cm.text_is_drawable(UPGRADES[u].what))
		testing.expect(t, cm.text_width(UPGRADES[u].name) <= 140)
	}
}

@(test)
test_the_prices_keep_the_pace_the_simulation_found :: proc(t: ^testing.T) {
	// A fresh player earns about 8 coins in the first run, so something must cost no more than that
	// much again; and the whole shop must stay big enough that maxing it takes hours, not minutes
	// (see sim_test.odin: about 2.4 hours for a good player with these prices).
	cheapest := max(int)
	total := 0
	for u in Upgrade {
		cheapest = min(cheapest, upgrade_cost(u, 0))
		for level in 0 ..< UPGRADES[u].max_level {
			total += upgrade_cost(u, level)
		}
	}
	testing.expect(t, cheapest <= 15)
	testing.expect(t, total >= 500_000)
}
