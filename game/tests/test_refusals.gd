extends TestCase
## Every refusal in PROTOCOL.md reads in plain words, with its own numbers, and money always as USDC.

const TYPES := ["AlreadyInRush", "NotInRush", "RushOver", "RushFull", "NoRunsLeft", "NoErrandsLeft", "NoMysteryLeft", "UnknownItem", "UnknownPlayer",
	"RefUsed", "MealPending", "NotEnoughEnergy", "EnergyFull", "FreeMealNotReady", "ChestNotReady", "WeeklyChestNotReady", "NoWallet", "NoVoucher",
	"NeedsTownPass", "BudgetSpent", "NoName", "NotAShockDay", "NotEnoughUsdc", "UnknownQuest", "AlreadyOnQuest", "NotOnQuest", "QuestDoneBefore",
	"WrongStep", "StepWaiting", "CampaignClosed", "NoSlotsLeft", "PerHumanCap", "BadSign", "AlreadyCalled", "AlreadyHuman", "ReferringYourself",
	"AlreadyReferred", "TooLateToRefer", "TryAgain", "NotEarned", "AlreadyCarved", "QuestionTooLong", "UnknownPost", "AlreadyReacted",
	"UnknownEmote", "FollowingYourself", "NotFollowing", "QuoteTooSoon", "QuoteStale"]

func test_every_refusal_has_words() -> void:
	for t in TYPES:
		var said := Refusals.say({"type": t}, 0)
		check(not said.begins_with("That didn't go through"), "%s has its own words" % t)
		check(not said.to_lower().contains("coin"), "%s: USDC is the only money" % t)

func test_the_numbers_are_the_refusals_own() -> void:
	eq(Refusals.say({"type": "NotEnoughEnergy", "have": 12.0, "need": 30.0}), "That takes 30 energy, and you have 12. Eat something first.", "energy")
	eq(Refusals.say({"type": "NotEnoughUsdc", "have": 4000.0, "need": 21738.0}), "That takes 0.021738 USDC and your wallet has 0.004 USDC.", "USDC, in full")
	eq(Refusals.say({"type": "RushFull", "most": 40.0}), "That's every customer this run has: 40.", "most")
	eq(Refusals.say({"type": "WeeklyChestNotReady", "days": 3.0, "need": 5.0}), "The weekly chest opens after 5 days of the last 7. You've come 3.", "days")
	eq(Refusals.say({"type": "FreeMealNotReady", "ready_at": 3600000.0}, 0), "The free thali is ready again in 1 h.", "on the real clock")
	eq(Refusals.say({"type": "WrongStep", "quest": "campaign:1", "step": "swap"}), "Not yet: first make the swap.", "the step to do next")

func test_an_unknown_refusal_still_says_something() -> void:
	eq(Refusals.say({"type": "SomethingNew"}), "That didn't go through (SomethingNew).", "named")

func test_a_chain_reason_reads_as_a_sentence() -> void:
	eq(Refusals.reason("no name to write on"), "No name to write on.", "capitalised, stopped")
	eq(Refusals.reason("V4TooLittleReceived"), "The price moved too far while swapping, past the slippage limit. Nothing was swapped.", "a known contract error")
	eq(Refusals.reason("MealCounter__PriceAboveMax"), "Price above max.", "an unknown one, in words")
	eq(Refusals.reason(null), "The chain didn't take it. Nothing was paid.", "no reason given")
