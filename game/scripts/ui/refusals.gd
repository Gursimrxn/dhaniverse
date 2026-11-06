class_name Refusals
## Why the server said no, in plain words, from the refusal's own numbers (PROTOCOL.md, Refusals and their numbers). Times are on the
## real clock, so they're read against TownClient.now_ms(). Money is USDC, always through Usdc. A refusal changes nothing, so every
## line says what is so and, where there is one, what to do about it.

const STEPS := {"talk": "talk to them", "visit": "go there", "paper": "read the paper", "strongbox": "open the strongbox",
	"cargo": "collect the cargo money", "swap": "make the swap", "deliver": "deliver the spice", "sign": "paint your sign",
	"verify": "get your Town Pass", "hold": "hold the token", "meals": "eat the meals"}

static func say(r: Dictionary, now := 0) -> String:
	var t := str(r.get("type", ""))
	match t:
		"AlreadyInRush": return "A run is already under way."
		"NotInRush": return "There's no run under way."
		"RushOver": return "That run is over."
		"RushFull": return "That's every customer this run has: %d." % int(r.get("most", 0))
		"NoRunsLeft": return "No runs left today: %d a day. More %s." % [int(r.get("most", 0)), TownState.soon(TownState.left_ms(r.get("resets_at"), now))]
		"NoErrandsLeft": return "That's today's %d errands done. More %s." % [int(r.get("most", 0)), TownState.soon(TownState.left_ms(r.get("resets_at"), now))]
		"NoMysteryLeft": return "Today's mystery is taken. A new one %s." % TownState.soon(TownState.left_ms(r.get("resets_at"), now))
		"UnknownItem": return "%s isn't on the menu." % str(r.get("item", "That"))
		"UnknownPlayer": return "Nobody in town goes by %s." % str(r.get("account", "that name"))
		"RefUsed": return "That already went through."
		"MealPending": return "Your last meal is still on its way to the chain."
		"NotEnoughEnergy": return "That takes %d energy, and you have %d. Eat something first." % [int(r.get("need", 0)), int(r.get("have", 0))]
		"EnergyFull": return "You're full: energy %d. Come back when you're hungry." % int(r.get("energy", 0))
		"FreeMealNotReady": return "The free thali is ready again %s." % TownState.soon(TownState.left_ms(r.get("ready_at"), now))
		"ChestNotReady": return "Your chest is ready again %s." % TownState.soon(TownState.left_ms(r.get("ready_at"), now))
		"WeeklyChestNotReady": return "The weekly chest opens after %d days of the last 7. You've come %d." % [int(r.get("need", 5)), int(r.get("days", 0))]
		"NoWallet": return "Your wallet isn't ready yet. It comes from the chain a few seconds after you arrive."
		"NoVoucher": return "You have no meal vouchers. They come in chests."
		"NeedsTownPass": return "That needs your Town Pass. Get it at the town hall, or on your phone's wallet page."
		"BudgetSpent": return "The town's budget for that is spent today. Try again tomorrow."
		"NoName": return "Your sign is written on your name, and that comes with your Town Pass."
		"NotAShockDay": return "Nothing big is happening in the market today. Come back when the paper has news of a festival, a harvest or a drought."
		"NotEnoughUsdc": return "That takes %s and your wallet has %s." % [Usdc.text(int(r.get("need", 0))), Usdc.text(int(r.get("have", 0)))]
		"UnknownQuest": return "That quest isn't on offer any more."
		"AlreadyOnQuest": return "You're already on that one. It's in your quest log."
		"NotOnQuest": return "You're not on that quest."
		"QuestDoneBefore": return "You've done that one before."
		"WrongStep": return "Not yet: first %s." % STEPS.get(str(r.get("step", "")), "the step before")
		"StepWaiting": return "Waiting for the chain on that one. It won't be long."
		"CampaignClosed": return "That sponsor's quest has closed."
		"NoSlotsLeft": return "Every place on that quest is taken."
		"PerHumanCap": return "You've done that sponsor's quest as often as one person may: %d." % int(r.get("cap", 1))
		"BadSign": return "A sign is one line of 1 to %d letters." % int(r.get("most", 80))
		"AlreadyCalled": return "You've made today's call. It settles when the next city day opens."
		"AlreadyHuman": return "You already hold your Town Pass."
		"ReferringYourself": return "You can't say you sent yourself."
		"AlreadyReferred": return "You've already said who sent you."
		"TooLateToRefer": return "Too late: that's for before your first quest is done."
		"QuoteTooSoon": return "The pool can be asked again %s." % TownState.soon(TownState.left_ms(r.get("ready_at"), now))
		"QuoteStale": return "That quote is too old to swap on. Get a new one, look at it, then swap."
		"TryAgain": return "The town hall couldn't make a pass link just now. Ask again."
		"NotEarned": return "That isn't earned yet."
		"AlreadyCarved": return "That's carved already."
		"QuestionTooLong": return "Keep it under %d letters." % int(r.get("max", 200))
		"UnknownPost": return "That post is too old to react to."
		"AlreadyReacted": return "You've reacted to that one."
		"UnknownEmote": return "That reaction isn't one of the town's."
		"FollowingYourself": return "You can't follow yourself."
		"NotFollowing": return "You're not following %s." % str(r.get("player", "them"))
		"NameTaken": return "Someone in town already goes by that."
		"BadName": return "Use 3 to 20 letters or numbers."
		"SlowDown": return "Too many tries. Wait a minute."
	return "That didn't go through (%s)." % t

## What the chain's own refusals (a contract's error, as the server passes it on) mean, in plain words.
const CHAIN := {
	"ERC20InsufficientBalance": "Your wallet didn't have enough USDC. Nothing was paid.",
	"V4TooLittleReceived": "The price moved too far while swapping, past the slippage limit. Nothing was swapped.",
	"CampaignEscrow__UnknownCampaign": "The chain doesn't know that sponsor's campaign.",
	"CampaignEscrow__AdvanceOpen": "The harbourmaster has already advanced you cargo money.",
	"CampaignEscrow__AdvanceTooBig": "That's more cargo money than he may advance.",
	"CampaignEscrow__NotLive": "That sponsor's campaign isn't running.",
	"CampaignEscrow__NoClaimsLeft": "Every place on that sponsor's quest is paid out.",
	"CampaignEscrow__PerHumanCap": "That sponsor has paid you as often as one person may be paid.",
	"CampaignEscrow__OverBudget": "That sponsor's budget can't cover it.",
	"CampaignEscrow__DailyCapReached": "That sponsor has paid out all they may today. It's paid tomorrow.",
	"SpiceMerchant__NotASpiceRun": "The Spice Merchant doesn't know this run.",
	"SpiceMerchant__NothingToDeliver": "You have no spice to deliver.",
}

## A reason the chain or the server gave (MealFailed, QuestStepFailed, QuestFailed), as a sentence. A contract's error it doesn't know
## reads as its words: "MealCounter__PriceAboveMax" -> "Price above max."
static func reason(text) -> String:
	var r := str(text if text != null else "").strip_edges()
	if r == "": return "The chain didn't take it. Nothing was paid."
	if CHAIN.has(r): return CHAIN[r]
	if r.contains("__"): r = r.get_slice("__", 1)
	if not r.contains(" "):            # CamelCase: split it into words
		var spaced := ""
		for i in r.length():
			if i > 0 and r[i] == r[i].to_upper() and r[i] != r[i].to_lower() and r[i - 1] == r[i - 1].to_lower(): spaced += " "
			spaced += r[i]
		r = spaced.to_lower()
	r = r.replace("_", " ")
	r = r[0].to_upper() + r.substr(1)
	return r if r.ends_with(".") else r + "."
