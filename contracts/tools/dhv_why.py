#!/usr/bin/env python3
"""dhv why: turn any revert from our contracts into plain words.

    python3 tools/dhv_why.py 0x<revert data>

It finds the error by its 4-byte selector in our compiled ABIs (ours, OpenZeppelin's and Uniswap's), decodes its
numbers, unwraps Uniswap's WrappedError around a hook's refusal, and prints the plain-English meaning from
docs/architecture/spec.json plus where in the code the error is raised.

Everything runs locally: decoding uses `cast decode-error --sig`, never an online signature lookup.
Coming later (Phase 5): `--tx <hash> --rpc <url>`, to explain a failed transaction on Arc or Sepolia directly.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

CONTRACTS = Path(__file__).resolve().parent.parent
SPEC = CONTRACTS.parent / "docs" / "architecture" / "spec.json"
OUT = CONTRACTS / "out"

BUILTIN = {
    "08c379a0": ("Error(string)", ["message"], "A plain text revert message."),
    "4e487b71": ("Panic(uint256)", ["code"], "A Solidity panic: overflow, division by zero, or a failed assert."),
}
WRAPPED = "WrappedError"


def keccak4(text):
    try:
        from Crypto.Hash import keccak  # pycryptodome, if installed
        return keccak.new(digest_bits=256, data=text.encode()).hexdigest()[:8]
    except ImportError:
        return subprocess.run(["cast", "keccak", text], capture_output=True, text=True, check=True).stdout.strip()[2:10]


def type_of(param):
    """ABI param -> canonical type string, including tuples."""
    t = param["type"]
    if t.startswith("tuple"):
        return "(" + ",".join(type_of(c) for c in param["components"]) + ")" + t[len("tuple"):]
    return t


def load_errors():
    """selector -> (signature, [arg names]) for every error in every compiled ABI."""
    found = {}
    for artifact in OUT.glob("*.sol/*.json"):
        try:
            abi = json.loads(artifact.read_text(encoding="utf-8")).get("abi", [])
        except (json.JSONDecodeError, OSError):
            continue
        for item in abi:
            if item.get("type") != "error":
                continue
            sig = f"{item['name']}({','.join(type_of(p) for p in item['inputs'])})"
            if sig not in {v[0] for v in found.values()}:
                found[keccak4(sig)] = (sig, [p["name"] or f"arg{i}" for i, p in enumerate(item["inputs"])])
    return found


def load_meanings():
    """error name -> (contract id, plain meaning) from the spec."""
    meanings = {}
    for contract in json.loads(SPEC.read_text(encoding="utf-8"))["contracts"]:
        for err in contract["errors"]:
            for part in err["sig"].split("·"):
                name = part.strip().split("(")[0]
                meanings.setdefault(name, (contract["id"], err["means"]))
    return meanings


def where(name):
    """Where the error is raised in our code, or where it's defined in a library."""
    hits = []
    for path in sorted((CONTRACTS / "src").rglob("*.sol")):
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if re.search(rf"\b{name}\b", line) and ("revert" in line or ".selector" in line):
                hits.append(f"contracts/{path.relative_to(CONTRACTS)}:{n}")
    if hits:
        return hits
    ens = CONTRACTS / "src" / "names" / "ENSv2.sol"
    for n, line in enumerate(ens.read_text(encoding="utf-8").splitlines(), 1) if ens.exists() else []:
        if re.search(rf"\berror {name}\(", line):
            return [f"inside ENS's own contracts on Sepolia (listed in contracts/src/names/ENSv2.sol:{n})"]
    for path in sorted((CONTRACTS / "lib").rglob("*.sol")):
        if "/test/" in str(path) or "/lib/" in str(path.relative_to(CONTRACTS / "lib")):
            continue
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if re.search(rf"\berror {name}\(", line):
                return [f"defined in contracts/{path.relative_to(CONTRACTS)}:{n} (a library; our code calls it)"]
    return ["not found in our code or libraries"]


def decode(sig, data):
    result = subprocess.run(["cast", "decode-error", "--sig", sig, data], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return [v.strip() for v in result.stdout.strip().splitlines()]


def explain(data, errors, meanings, depth=0):
    pad = "  " * depth
    data = data.lower()
    if not data.startswith("0x"):
        data = "0x" + data
    selector = data[2:10]
    if selector in BUILTIN:
        sig, arg_names, meaning = BUILTIN[selector]
    elif selector in errors:
        sig, arg_names = errors[selector]
        meaning = None
    else:
        print(f"{pad}✗ Unknown error 0x{selector}. Run forge build, or it comes from a contract we don't compile.")
        return
    name = sig.split("(")[0]
    values = decode(sig, data) if arg_names else []
    _, spec_meaning = meanings.get(name, (None, None))
    meaning = meaning or spec_meaning or "(no plain-English line in the spec yet: add one)"
    if "__" in name:
        headline = f"{name.split('__')[0]} refused · {name}"
    elif name == WRAPPED:
        headline = f"Uniswap's PoolManager refused · {name}"
    elif any("ENS" in w for w in where(name)):
        headline = f"ENS refused · {name}"
    else:
        # A library error (OpenZeppelin, Uniswap): which of our contracts hit it needs the transaction's trace.
        headline = f"Refused by a library check · {name}"

    print(f"{pad}✗ {headline}")
    if values:
        print(pad + "  " + " · ".join(f"{k} {v}" for k, v in zip(arg_names, values)))
    if name == WRAPPED and values and len(values) >= 3:
        print(f"{pad}  Unwrapped  Uniswap wrapped a refusal from {values[0]}. The real reason:")
        explain(values[2], errors, meanings, depth + 1)
        return
    print(f"{pad}  Meaning  {meaning}")
    for i, place in enumerate(where(name)):
        print(f"{pad}  {'Where    ' if i == 0 else '         '}{place}")


def main():
    if len(sys.argv) != 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0 if len(sys.argv) == 2 else 2)
    if not OUT.exists():
        sys.exit("No compiled contracts. Run forge build first.")
    print(f"$ dhv why {sys.argv[1][:10]}…")
    explain(sys.argv[1], load_errors(), load_meanings())


if __name__ == "__main__":
    main()
