#!/usr/bin/env python3
"""spec_check: the code and its plain-English spec must say the same thing.

For every contract of ours that exists in src/, it compares the compiled ABI with
docs/architecture/spec.json and fails if:
  - a public function, event or our own error (Contract__Problem) has no line in the spec, or
  - the spec lists a function, event or error of ours that the code doesn't have, or
  - a spec line has no plain-English "does" / "means".

Contracts the spec lists but that aren't written yet are reported as "not built yet", not as failures.

Run after `forge build`:  python3 tools/spec_check.py
"""
import json
import sys
from pathlib import Path

CONTRACTS = Path(__file__).resolve().parent.parent
SPEC = CONTRACTS.parent / "docs" / "architecture" / "spec.json"
OUT = CONTRACTS / "out"


def names(sig_field):
    """'transfer · approve(x) → y' -> {'transfer', 'approve'}"""
    found = set()
    for part in sig_field.split("·"):
        name = part.strip().split("(")[0].split(" ")[0].strip()
        if name:
            found.add(name)
    return found


def check(contract):
    cid = contract["id"]
    source = CONTRACTS / contract["file"]
    if not source.exists():
        return [], f"  … {cid}: not built yet"

    artifact = OUT / source.name / f"{cid}.json"
    if not artifact.exists():
        return [f"{cid}: {source.relative_to(CONTRACTS)} exists but isn't compiled. Run forge build first."], None
    abi = json.loads(artifact.read_text(encoding="utf-8"))["abi"]

    problems = []
    code_fns = {x["name"] for x in abi if x["type"] == "function"}
    code_events = {x["name"] for x in abi if x["type"] == "event"}
    prefix = f"{cid}__"
    code_errors = {x["name"] for x in abi if x["type"] == "error" and x["name"].startswith(prefix)}

    spec_fns = set()
    for fn in contract["fns"]:
        if not fn.get("does", "").strip():
            problems.append(f"{cid}: '{fn['sig']}' has no plain-English 'does' line.")
        spec_fns |= names(fn["sig"])
    spec_fns.discard("constructor")
    spec_events = set().union(*(names(e["sig"]) for e in contract["events"])) if contract["events"] else set()
    spec_errors = set()
    for err in contract["errors"]:
        if not err.get("means", "").strip():
            problems.append(f"{cid}: error '{err['sig']}' has no plain-English 'means' line.")
        spec_errors |= {n for n in names(err["sig"]) if n.startswith(prefix)}

    for kind, code, spec in (("function", code_fns, spec_fns), ("event", code_events, spec_events),
                             ("error", code_errors, spec_errors)):
        for missing in sorted(code - spec):
            problems.append(f"{cid}: public {kind} '{missing}' is in the code but has no line in the spec.")
        for extra in sorted(spec - code):
            problems.append(f"{cid}: the spec lists {kind} '{extra}', but the code doesn't have it.")

    summary = f"  ✓ {cid}: {len(code_fns)} functions, {len(code_events)} events, {len(code_errors)} errors of ours"
    return problems, (summary if not problems else None)


def main():
    sys.stdout.reconfigure(encoding="utf-8")  # the report uses ✓ and ✗, on Windows consoles too
    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    ours = [c for c in spec["contracts"] if c["ours"] and c["file"].startswith("src/")]
    all_problems = []
    print("spec_check: does the code match docs/architecture/spec.json?")
    for contract in ours:
        problems, line = check(contract)
        all_problems += problems
        if line:
            print(line)
    if all_problems:
        print(f"\n✗ {len(all_problems)} mismatch(es). Fix the code or the spec, so they say the same thing:")
        for p in all_problems:
            print(f"  - {p}")
        sys.exit(1)
    print("\n✓ Code and spec agree.")


if __name__ == "__main__":
    main()
