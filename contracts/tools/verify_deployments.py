#!/usr/bin/env python3
"""Checks contracts/deployments/sepolia.json against the latest broadcast's receipts and the chain itself.

Usage (from contracts/, with SEPOLIA_RPC_URL set): python tools/verify_deployments.py . [--fix]
With --fix, rewrites the file's addresses, pool ids, position id, campaign id and startBlock from what the chain says.
"""
import json, os, subprocess, sys

root = sys.argv[1]
fix = "--fix" in sys.argv
rpc = os.environ["SEPOLIA_RPC_URL"]
dep_path = os.path.join(root, "deployments/sepolia.json")
bc = json.load(open(os.path.join(root, "broadcast/Deploy.s.sol/11155111/run-latest.json")))
dep = json.load(open(dep_path))


def cast(*args):
    r = subprocess.run(["cast", *args, "--rpc-url", rpc], capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(f"cast {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout.strip()


def cs(a):
    return subprocess.run(["cast", "to-check-sum-address", a], capture_output=True, text=True).stdout.strip()


def pool_id(c0, c1, fee, ts, hooks):
    enc = subprocess.run(["cast", "abi-encode", "f(address,address,uint24,int24,address)", c0, c1, str(fee), str(ts), hooks],
                         capture_output=True, text=True).stdout.strip()
    return subprocess.run(["cast", "keccak", enc], capture_output=True, text=True).stdout.strip()


rc = {r["transactionHash"]: r for r in bc["receipts"]}
txs = bc["transactions"]
bad_tx = [i for i, t in enumerate(txs) if t.get("hash") not in rc or rc[t["hash"]]["status"] != "0x1"]
if bad_tx:
    raise SystemExit(f"broadcast has {len(bad_tx)} transaction(s) without a successful receipt: {bad_tx[:5]}")

problems = []
want = {t["contractName"]: cs(t["contractAddress"]) for t in txs if t["transactionType"] in ("CREATE", "CREATE2")}
for name, addr in want.items():
    if cs(dep["contracts"].get(name, "0x0")) != addr:
        problems.append(f"contracts.{name}: file {dep['contracts'].get(name)} chain {addr}")
    if cast("codesize", addr) in ("0", ""):
        problems.append(f"{name} at {addr} has no code")
    dep["contracts"][name] = addr

first_block = min(int(rc[t["hash"]]["blockNumber"], 16) for t in txs)
if dep["startBlock"] > first_block:
    problems.append(f"startBlock {dep['startBlock']} is after the first deploy transaction's block {first_block}")
    dep["startBlock"] = first_block

usdc = cs(dep["usdc"])
uni = dep["uniswap"]
key = cast("call", want["FoodRouter"], "poolKey()((address,address,uint24,int24,address))").strip("()").split(", ")
c0, c1, fee, ts, hooks = cs(key[0]), cs(key[1]), int(key[2]), int(key[3]), cs(key[4])
fid = pool_id(c0, c1, fee, ts, hooks)
fp = uni["foodPool"]
for k, v in (("currency0", c0), ("currency1", c1), ("hooks", hooks)):
    if cs(fp[k]) != v:
        problems.append(f"uniswap.foodPool.{k}: file {fp[k]} chain {v}")
    fp[k] = v
if fp["poolId"].lower() != fid.lower():
    problems.append(f"uniswap.foodPool.poolId: file {fp['poolId']} chain {fid}")
fp["poolId"] = fid

mango = want["QuestToken"]
qc0, qc1 = sorted([usdc, mango], key=lambda a: int(a, 16))
qp = uni["questPool"]
qid = pool_id(qc0, qc1, qp["fee"], qp["tickSpacing"], "0x0000000000000000000000000000000000000000")
for k, v in (("currency0", qc0), ("currency1", qc1)):
    if cs(qp[k]) != v:
        problems.append(f"uniswap.questPool.{k}: file {qp[k]} chain {v}")
    qp[k] = v
if qp["poolId"].lower() != qid.lower():
    problems.append(f"uniswap.questPool.poolId: file {qp['poolId']} chain {qid}")
qp["poolId"] = qid

TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
pos = None
for t in txs:
    if (t.get("function") or "").startswith("modifyLiquidities"):
        for lg in rc[t["hash"]]["logs"]:
            tp = lg["topics"]
            if tp[0] == TRANSFER and len(tp) == 4 and int(tp[1], 16) == 0:
                pos = int(tp[3], 16)
if pos is None:
    problems.append("no PositionManager mint found in the broadcast")
elif qp["positionId"] != pos:
    problems.append(f"uniswap.questPool.positionId: file {qp['positionId']} chain {pos}")
    qp["positionId"] = pos

sv = uni["stateView"]
for name, pid in (("food", fid), ("quest", qid)):
    liq = int(cast("call", sv, "getLiquidity(bytes32)(uint128)", pid).split()[0])
    if liq == 0:
        problems.append(f"{name} pool {pid} has no liquidity")

count = int(cast("call", want["CampaignEscrow"], "campaignCount()(uint256)").split()[0])
if dep["demoCampaignId"] != count:
    problems.append(f"demoCampaignId: file {dep['demoCampaignId']} chain {count}")
    dep["demoCampaignId"] = count

if cast("call", want["FoodToken"], "allowlistLocked()(bool)") != "true":
    problems.append("FoodToken's allowlist isn't locked")

if problems:
    print("PROBLEMS:")
    for p in problems:
        print("  -", p)
    if fix:
        json.dump(dep, open(dep_path, "w"), indent=2)
        open(dep_path, "a").write("\n")
        print("rewrote", dep_path, "- run again to confirm")
    sys.exit(1)
print(f"OK: {len(want)} contracts, both pools, position {pos}, campaign {count}, startBlock {dep['startBlock']} "
      f"(first tx block {first_block}) all match the chain")
