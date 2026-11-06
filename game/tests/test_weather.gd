extends TestCase
## The shared calendar (spec 6.2, 6.3): a season lasts 7 real days, weather changes on the hour from a seeded
## schedule everyone shares, and never snows in summer.

const Weather := preload("res://scripts/world/weather.gd")
const DAY := 86400.0

func test_a_season_lasts_seven_days_and_they_turn_in_order() -> void:
	var t0 := 1_800_000_000.0
	var s0: String = Weather.season_at(t0)
	var i0: int = Weather.SEASONS.find(s0)
	eq(Weather.season_at(t0 + 6.0 * 3600.0), s0, "same season six hours on")
	var later: String = Weather.season_at(t0 + 7.0 * DAY)
	eq(later, Weather.SEASONS[(i0 + 1) % 4], "the next season a week on")

func test_weather_holds_for_the_hour_and_is_shared() -> void:
	var t := 1_800_000_000.0 - fmod(1_800_000_000.0, 3600.0) + 60.0
	eq(Weather.weather_at(t), Weather.weather_at(t + 3000.0), "changed within the hour")

func test_no_snow_outside_winter_and_every_kind_happens() -> void:
	var seen := {}
	var t := 1_800_000_000.0
	for h in 28 * 24:
		var w: String = Weather.weather_at(t + h * 3600.0)
		var s: String = Weather.season_at(t + h * 3600.0)
		seen[w] = true
		check(not (w == "snow" and s != "winter"), "snow in %s" % s)
	for w in ["clear", "overcast", "rain", "mist", "snow"]:
		check(seen.has(w), "%s never happened in a year" % w)
