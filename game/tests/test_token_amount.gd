extends TestCase
## The exchange kiosk's quote, as the player reads it (PROTOCOL.md, The exchange kiosk): an 18-decimal token amount sent as a string of
## digits, "about" rounded to the nearest, "at least" never rounded up, the pool's fee and the slippage limit as percentages.

const QUOTE := {"usdc_in": 500000.0, "amount_out": "9066109666030017277", "min_out": "8975448569369717104", "fee_bps": 3000.0,
	"slippage_bps": 100.0, "token": "0x…", "symbol": "MANGO", "decimals": 18.0, "quoted_at": 61000.0, "fresh_until": 121000.0}

func test_an_amount_reads_in_whole_tokens() -> void:
	eq(TokenAmount.about("9066109666030017277", 18), "9.07", "about: rounded to the nearest")
	eq(TokenAmount.about("9064999999999999999", 18), "9.06", "just under the half rounds down")
	eq(TokenAmount.about("9995000000000000000", 18), "10.00", "a carry through the nines")
	eq(TokenAmount.about("1000000000000000000000", 18), "1000.00", "bigger than a number here holds")
	eq(TokenAmount.about("0", 18), "0", "nothing")
	eq(TokenAmount.about("not a number", 18), "0", "rubbish reads as nothing, not a crash")

func test_the_least_youll_take_is_never_overstated() -> void:
	eq(TokenAmount.at_least("8975448569369717104", 18), "8.97", "cut down, not rounded up to 8.98")
	eq(TokenAmount.at_least("8999999999999999999", 18), "8.99", "even a hair under")

func test_a_small_amount_keeps_its_figures() -> void:
	eq(TokenAmount.about("1234500000000000", 18), "0.00123", "three figures after the zeros")
	eq(TokenAmount.at_least("1239999999999999", 18), "0.00123", "cut, not rounded")
	eq(TokenAmount.about("15", 2), "0.15", "a token of 2 decimals")
	eq(TokenAmount.about("1500", 0), "1500", "a token with no decimals")

func test_fee_and_slippage_read_as_percentages() -> void:
	eq(TokenAmount.fee(3000), "0.30%", "Uniswap's 3000 is 0.30%")
	eq(TokenAmount.fee(500.0), "0.05%", "and 500 is 0.05%")
	eq(TokenAmount.bps(100), "1%", "100 basis points")
	eq(TokenAmount.bps(50.0), "0.5%", "50")
	eq(TokenAmount.bps(125), "1.25%", "125")

func test_the_quote_in_plain_words() -> void:
	eq(SpiceRun.quote_words(QUOTE), "0.50 USDC buys about 9.07 MANGO. The pool keeps 0.30%. If the price moves, you'll still get at least 8.97 MANGO, or the swap won't happen.", "the kiosk's sentence")
