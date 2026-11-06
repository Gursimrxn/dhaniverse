class_name StallShift
extends RefCounted
## The rules of serving behind a stall in a Market Rush run, with no scene in them: the orders waiting, what the worker holds and
## what pressing the key does now. scripts/market/stall.gd shows all of this; the run's count is the server's (TownClient).

enum Do { NOTHING, TAKE, SWAP, PUT_BACK, SERVE, REFUSE }

var held := ""                   # the item in the worker's hands
var orders: Array[Dictionary] = []   # {id, item}, the front of the queue first
var _next_id := 1

func add_order(item: String) -> int:
	orders.append({"id": _next_id, "item": item})
	_next_id += 1
	return orders.back().id

## Someone gave up and went: their order goes with them.
func drop(id: int) -> void:
	orders = orders.filter(func(o): return o.id != id)

func wanted() -> String:
	return str(orders[0].item) if not orders.is_empty() else ""

## What the key would do for a worker standing at a crate ("": at none).
func action(at_crate: String) -> Do:
	if held == "": return Do.TAKE if at_crate != "" else Do.NOTHING
	if held == wanted(): return Do.SERVE
	if at_crate == held: return Do.PUT_BACK
	if at_crate != "": return Do.SWAP
	return Do.REFUSE if not orders.is_empty() else Do.NOTHING

## Press the key. Returns what was done, and for SERVE the order that was filled in `served`.
var served := {}

func press(at_crate: String) -> Do:
	var what := action(at_crate)
	match what:
		Do.TAKE, Do.SWAP: held = at_crate
		Do.PUT_BACK: held = ""
		Do.SERVE:
			served = orders.pop_front()
			held = ""
	return what

## The worker walked away: what they carried goes back on its crate.
func leave() -> void:
	held = ""
