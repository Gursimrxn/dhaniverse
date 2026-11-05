#!/usr/bin/env python3
"""Build the architecture docs from spec.json, the single source of truth.

Outputs:
  Contracts_Architecture.md    the readable reference: every contract, every button
  Contracts_Architecture.html  the interactive visual; opens in any browser

Edit spec.json, then run:  python3 build_docs.py
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = HERE / "spec.json"
TEMPLATE = HERE / "_template.html"
OUT_MD = HERE / "Contracts_Architecture.md"
OUT_HTML = HERE / "Contracts_Architecture.html"

LANES = {"game": "Game", "server": "Server", "chain": "Arc"}
FIT = {"easy": "✓ Easy", "no": "✗ No"}
KIND = {
    "building": "Contract (ours)",
    "wallet": "Wallet (one per citizen)",
    "library": "Library: pure maths",
    "token": "Token",
    "hook": "Uniswap hook",
    "base": "Shared base",
    "external": "Not ours",
}


def cell(text):
    """Make text safe inside a Markdown table cell."""
    return str(text).replace("|", "\\|").replace("\n", " ")


def table(headers, rows):
    lines = ["| " + " | ".join(headers) + " |", "|" + "---|" * len(headers)]
    lines += ["| " + " | ".join(cell(c) for c in row) + " |" for row in rows]
    return "\n".join(lines)


def slug(text):
    """GitHub-style heading anchor."""
    keep = "".join(ch for ch in text.lower() if ch.isalnum() or ch in " -")
    return keep.replace(" ", "-")


def floor_label(floor):
    return "Off-chain" if floor["id"] == "roof" else f"Layer {floor['n']}"


def contract_md(c):
    out = [
        f"#### {c['emoji']} {c['id']} · {c['nick']}",
        "",
        f"**What it is.** {c['one']}",
        "",
        f"**In the game.** {c['game']}",
        "",
        f"- **File:** `{c['file']}`",
        f"- **Kind:** {KIND.get(c['kind'], c['kind'])}",
        f"- **Upgrade:** {c['upgrade']}",
        f"- **Off switch:** {c['fuse']}",
        f"- **Stores:** {'; '.join(c['remembers'])}",
        f"- **Calls or reads:** {', '.join(c['talksTo']) if c['talksTo'] else 'nothing (other contracts read it)'}",
        "",
        f"**Functions ({len(c['fns'])})**",
        "",
        table(
            ["Function", "Who calls it", "When", "What happens"],
            [[f"`{f['sig']}`" + (" *(read)*" if f.get("read") else ""), f["who"], f["when"], f["does"]] for f in c["fns"]],
        ),
        "",
    ]
    if c["events"]:
        out += ["**Events**", "", table(["Event", "Means"], [[f"`{e['sig']}`", e["means"]] for e in c["events"]]), ""]
    if c["errors"]:
        out += ["**Errors**", "", table(["Error", "Means"], [[f"`{e['sig']}`", e["means"]] for e in c["errors"]]), ""]
    return out


def build_md(s):
    m = s["meta"]
    floors = {f["id"]: f for f in s["floors"]}
    by_floor = {}
    for c in s["contracts"]:
        by_floor.setdefault(c["floor"], []).append(c)
    ours = [c for c in s["contracts"] if c["ours"] and c["kind"] not in ("library", "base")]
    n_libs = sum(1 for c in s["contracts"] if c["kind"] == "library")
    n_bases = sum(1 for c in s["contracts"] if c["kind"] == "base")
    n_ext = sum(1 for c in s["contracts"] if not c["ours"])
    n_fns = sum(len(c["fns"]) for c in s["contracts"])
    counts = [f"{len(ours)} contracts of ours"]
    if n_libs:
        counts.append(f"{n_libs} maths libraries")
    if n_bases:
        counts.append(f"{n_bases} shared base")
    counts.append(f"{n_ext} that aren't ours")
    checked = m.get("checked", "Checked")

    L = [
        f"# {m['title']}",
        "",
        f"**Status:** {m['status']}  ",
        f"**Version:** {m['version']}, {m['date']}.  ",
        "**Visual:** [Contracts_Architecture.html](Contracts_Architecture.html), which opens in any browser.  ",
        f"**Sits on:** {m['sitsOn']}",
        "",
        "> Generated from `spec.json` by `build_docs.py`. Edit the spec, then run `python3 build_docs.py`, so this doc and the visual never disagree.",
        "",
        "## Contents",
        "",
        "0. [The 30-second version](#0-the-30-second-version)",
        "1. [Five promises](#1-five-promises)",
        "2. [How we work, every phase](#2-how-we-work-every-phase)",
        "3. [The contracts, layer by layer](#3-the-contracts-layer-by-layer)",
        "4. [Off-chain helpers](#4-off-chain-helpers)",
        "5. [Two speeds: what waits for the chain](#5-two-speeds-what-waits-for-the-chain)",
        "6. [When something breaks](#6-when-something-breaks)",
        "7. [Phases, bottom to top](#7-phases-bottom-to-top)",
        "8. [Decisions I've made for you](#8-decisions-ive-made-for-you)",
        "9. [Arc Studio: where it fits](#9-arc-studio-where-it-fits)",
        "10. [Rules of the code](#10-rules-of-the-code)",
        "11. [Numbers the tests must hit](#11-numbers-the-tests-must-hit)",
        "12. [Words](#12-words)",
        f"13. [{checked}](#{slug('13. ' + checked)})",
        "",
        "---",
        "",
        "## 0. The 30-second version",
        "",
        s["summary"],
        "",
        f"In numbers: {', '.join(counts[:-1])} and {counts[-1]}, {n_fns} functions in all. Every one is listed in §3.",
        "",
        "**What I need from you:**",
        "",
    ]
    L += [f"{i}. {x}" for i, x in enumerate(s["needFromYou"], 1)]
    L += ["", "## 1. Five promises", ""]
    L += [f"- {p['icon']} **{p['title']}.** {p['text']}" for p in s["promises"]]
    L += ["", "## 2. How we work, every phase", ""]
    L += [f"{w['n']}. **{w['title']}.** {w['text']}" for w in s["workLoop"]]

    L += [
        "",
        "## 3. The contracts, layer by layer",
        "",
        "Layers are built bottom to top (§7).",
        "",
        table(
            ["Layer", "Contract", "What it is", "Kind", "Upgrade", "Off switch"],
            [
                [floor_label(floors[c["floor"]]), c["id"], c["nick"], KIND.get(c["kind"], c["kind"]), c["upgrade"], c["fuse"]]
                for f in sorted(s["floors"], key=lambda f: f["n"])
                for c in by_floor.get(f["id"], [])
            ],
        ),
        "",
    ]
    for f in sorted(s["floors"], key=lambda f: f["n"]):
        if f["id"] == "roof":
            continue
        plain = f["plain"][0].lower() + f["plain"][1:]
        L += [f"### {floor_label(f)} · {f['name']}: {plain}", "", f"Phase {f['phase']} · {f['chapter']} · `{f['folder']}`", ""]
        for c in by_floor.get(f["id"], []):
            L += contract_md(c)

    L += ["## 4. Off-chain helpers", "", m["roofOne"], ""]
    L += [table(["Helper", "What it does"], [[f"{o['emoji']} {o['name']}", o["does"]] for o in s["offchain"]]), ""]

    L += ["## 5. Two speeds: what waits for the chain", "", table(["Moment", "Examples", "Wait"], [[f"{x['icon']} {x['title']}", x["text"], x["wait"]] for x in s["moments"]]), ""]
    for fl in s["flows"]:
        rows = []
        for n, st in enumerate(fl["steps"], 1):
            where = st.get("on", LANES[st["lane"]]) if st["lane"] == "chain" else LANES[st["lane"]]
            if st.get("group"):
                group = st["group"].removeprefix(f"{st['t']} · ")
                where += f" · {group}"
            if st.get("par") and st["t"] != "alongside":
                where += " (alongside)"
            rows.append([n, st["t"], where, st["text"]])
        L += [f"### {fl['title']} ({fl['tag']})", "", fl["lede"], "", table(["Step", "When", "Where", "What happens"], rows), "", f"*{fl['foot']}*", ""]

    L += ["## 6. When something breaks", "", "### Find it in seconds", "", "Example output of `dhv why`. The line numbers are placeholders until the code exists.", ""]
    for d in s["errorDemos"]:
        L += [f"**{d['label']}**", "", "```text", *d["lines"], "```", ""]
    L += [
        "### Switch one piece off, and the rest keep working",
        "",
        m["fuseNote"],
        "",
        table(["Switch off", "What stops", "What keeps working"], [[f"{f['id']}: {f.get('label', 'off')}", "; ".join(f["stops"]), "; ".join(f["keeps"])] for f in s["fuses"]]),
        "",
        "### Fix it without breaking anything",
        "",
    ]
    L += [f"{i}. **{x['t']}.** {x['d']}" for i, x in enumerate(s["fixSteps"], 1)]

    L += [
        "",
        "## 7. Phases, bottom to top",
        "",
        "Each phase runs the loop in §2 and ends with something you can run yourself. Sizes are relative (S, M, L).",
        "",
        m.get("phasesHint", ""),
        "",
    ]
    if s.get("prep"):
        L += ["### Before the first phase", "", *[f"- {x}" for x in s["prep"]], ""]
    L += [
        table(
            ["#", "Phase", "Layer", "Chapter", "Size", "Side by side"],
            [[p["n"], p["name"], floor_label(floors[p["floor"]]), p["chapter"] or "", p["size"], p["parallel"] or ""] for p in s["phases"]],
        ),
        "",
    ]
    for p in s["phases"]:
        L += [f"### Phase {p['n']}: {p['name']}", "", f"**Builds:** {'; '.join(p['builds'])}.", "", f"**You'll see:** {p['see']}", "", "**Done when:**", ""]
        L += [f"- {d}" for d in p["done"]]
        if p["studio"]:
            L += ["", f"**Arc Studio:** {p['studio']}"]
        if p["parallel"]:
            L += ["", f"**Note:** {p['parallel']}"]
        L.append("")

    L += ["## 8. Decisions I've made for you", "", "Each is my pick. Say no to any and the map changes.", ""]
    for i, d in enumerate(s["decisions"], 1):
        L += [f"{i}. **{d['q']}** ✓ {d['pick']}", f"   - *Why:* {d['why']}", f"   - *Instead:* {d['alt']}"]
    if s.get("notOnChain"):
        L += ["", "### Considered, and kept off-chain", "", table(["What", "Why it stays off-chain"], [[x["what"], x["why"]] for x in s["notOnChain"]])]
    L += ["", "## 9. Arc Studio: where it fits", "", table(["Where", "How", "Fits?"], [[x["where"], x["how"], FIT.get(x["fit"], "? " + x["fit"].capitalize())] for x in s["studio"]]), ""]
    L += ["## 10. Rules of the code", ""]
    L += [f"{i}. **{r['t']}.** {r['d']}" for i, r in enumerate(s["rules"], 1)]
    L += ["", "## 11. Numbers the tests must hit", "", table(["What", "Number", "Phase"], [[n["what"], n["value"], n["phase"]] for n in s["numbers"]]), ""]
    L += ["## 12. Words", "", table(["Word", "Plain meaning", "Like"], [[w["w"], w["d"], w["like"]] for w in s["words"]]), ""]
    L += [f"## 13. {checked}", ""]
    L += [f"- {x['fact']}" + (f" ([source]({x['src']}))" if x["src"] else "") for x in s["facts"]]
    L.append("")
    return "\n".join(L)


def build_html(s):
    data = json.dumps(s, ensure_ascii=False).replace("</", "<\\/")
    return TEMPLATE.read_text(encoding="utf-8").replace("__SPEC_JSON__", data)


def main():
    s = json.loads(SPEC.read_text(encoding="utf-8"))
    OUT_MD.write_text(build_md(s), encoding="utf-8")
    OUT_HTML.write_text(build_html(s), encoding="utf-8")
    print(f"wrote {OUT_MD.name} and {OUT_HTML.name}")


if __name__ == "__main__":
    main()
