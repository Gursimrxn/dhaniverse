class_name Usdc
## How money reads in the game: USDC, from the server's base units (1000000 is 1 USDC). Text only; no sums are done here.

const UNITS := 1000000

## 1020 -> "0.00102 USDC", 1500000 -> "1.50 USDC": every digit there is, and at least two after the point.
static func text(units: int) -> String:
	return amount(units) + " USDC"

## The figure alone, for where the unit is already said: 1020 -> "0.00102", -20 -> "-0.00002".
static func amount(units: int) -> String:
	var fraction := str(absi(units) % UNITS).lpad(6, "0").rstrip("0")
	return "%s%d.%s" % ["-" if units < 0 else "", absi(units) / UNITS, fraction.rpad(2, "0")]
