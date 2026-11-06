extends TestCase
## How a USDC amount reads: the server's base units (1000000 is 1 USDC) as text, with nothing rounded away.

func test_menu_prices_read_in_full() -> void:
	eq(Usdc.text(1000), "0.001 USDC", "a thousand units")
	eq(Usdc.text(1020), "0.00102 USDC", "every digit there is")
	eq(Usdc.text(1), "0.000001 USDC", "the smallest")

func test_whole_amounts_keep_two_places() -> void:
	eq(Usdc.text(0), "0.00 USDC", "nothing")
	eq(Usdc.text(1000000), "1.00 USDC", "one")
	eq(Usdc.text(1500000), "1.50 USDC", "one and a half")
	eq(Usdc.text(12345678), "12.345678 USDC", "more than one")

func test_a_change_has_its_sign_and_no_unit() -> void:
	eq(Usdc.amount(-20), "-0.00002", "down")
	eq(Usdc.amount(20), "0.00002", "up: the tag puts the plus")
	eq(Usdc.amount(-1500000), "-1.50", "a whole one, down")
