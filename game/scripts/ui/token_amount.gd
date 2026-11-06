class_name TokenAmount
## How a quest token's amount reads (the exchange kiosk's quote, PROTOCOL.md): the server sends it as a decimal string in the token's base
## units (18 decimals for MANGO), too big for a number here, so it's read as digits. "9066108938801491315" -> "9.07". Text only: the
## server worked the amounts out; this only shows them. Rates in basis points read as percentages.

## About this much: rounded to the nearest, two places (more for a small amount, so it never reads as 0).
static func about(base_units: String, decimals: int) -> String:
	return _shown(base_units, decimals, false)

## At least this much: cut down, never rounded up, so the least you'll accept is never overstated.
static func at_least(base_units: String, decimals: int) -> String:
	return _shown(base_units, decimals, true)

## Uniswap's fee, in hundredths of a basis point: 3000 -> "0.30%".
static func fee(fee_bps) -> String:
	return "%.2f%%" % (int(fee_bps) / 10000.0)

## Basis points as a percentage, no trailing zeros: 100 -> "1%", 50 -> "0.5%", 125 -> "1.25%".
static func bps(points) -> String:
	return ("%.2f" % (int(points) / 100.0)).rstrip("0").trim_suffix(".") + "%"

static func _shown(base_units: String, decimals: int, down: bool) -> String:
	var digits := base_units.strip_edges().lstrip("0")
	if digits == "" or not digits.is_valid_int(): return "0"
	digits = digits.lpad(decimals + 1, "0")
	var whole := digits.left(digits.length() - decimals)
	var frac := digits.right(decimals) if decimals > 0 else ""
	var places := 2
	if whole == "0":                   # a small amount: keep three figures after the first that isn't 0
		var first := 0
		while first < frac.length() and frac[first] == "0": first += 1
		places = mini(first + 3, decimals)
	places = mini(places, decimals)
	var kept := (whole + frac.left(places))
	var rest := frac.substr(places)
	if not down and rest != "" and int(rest[0]) >= 5: kept = _plus_one(kept)
	var w := kept.left(kept.length() - places).lstrip("0")
	var f := kept.right(places) if places > 0 else ""
	return (w if w != "" else "0") + ("." + f if f != "" else "")

## A string of digits, plus one in its last place.
static func _plus_one(digits: String) -> String:
	var out := digits.to_ascii_buffer()
	var i := out.size() - 1
	while i >= 0:
		if out[i] == 57:               # '9'
			out[i] = 48
			i -= 1
		else:
			out[i] += 1
			return out.get_string_from_ascii()
	return "1" + out.get_string_from_ascii()
