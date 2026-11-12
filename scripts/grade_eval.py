#!/usr/bin/env python3
"""Blind-grade two arms of a run and emit benchmarks/results/ verdict files.

Pairs the with-skill and baseline responses for a skill, shows both to one
grader per eval under neutral labels, and scores every expectation
pass / partial / fail with a verbatim evidence quote.

Three properties this is built to preserve, all of which benchmarks/README.md
commits to and all of which are easy to lose:

  Blind.      The grader sees "Answer A" and "Answer B" and is not told which
              is which. The label order is shuffled per eval from a seed
              derived from the run id, so it is reproducible but not guessable
              from the eval number.
  One grader. Both arms of an eval are scored in a single call. A delta between
              two arms graded by different graders measures the graders —
              this repo has that drift documented at -6.9 to +0.9.
  Evidence.   Every verdict carries a quote. A verdict with no quote is an
              assertion, and assertions are what let a stale benchmark survive.

    scripts/grade_eval.py --skill argo-knowledge --run-id 2026-11-10 \
        --run-label "2026-11-10 run 9, post-narrowing"

Writes benchmarks/results/<skill>.{with-skill,baseline}.results.json in the
schema scripts/check-published-numbers.py reads, so the integrity check will
immediately tell you if a published table has drifted from these verdicts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import random
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

GRADER_INSTRUCTIONS = """\
Score each candidate answer against the expectation list.

You do NOT know how these answers were produced, and they are NOT ranked. Do not
speculate about their origin. Judge only the text in front of you.

For EVERY answer and EVERY expectation, give:
  verdict  - "pass" (fully met), "partial" (partly met), or "fail" (not met)
  evidence - a short verbatim quote from THAT answer supporting the verdict,
             or "absent" if nothing in it addresses the expectation

Do not reward length, confidence or formatting. An answer that states something
correctly in one line beats one that gestures at it over a page. An answer that
asserts something the expectation does not ask for earns nothing for it.

Output ONLY JSON, no prose:
{"A": [{"n": 1, "verdict": "pass", "evidence": "..."}, ...], "B": [...]}
"""


def skill_dir(skill: str) -> pathlib.Path:
    hits = sorted(ROOT.glob(f"skills/*/{skill}"))
    if not hits:
        sys.exit(f"no skill directory for {skill!r}")
    return hits[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skill", required=True)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--run-label", required=True, help="goes in the verdict files' 'run' field")
    ap.add_argument("--grader-model", default="claude-opus-5")
    ap.add_argument("--model", default="claude-opus-5", help="model recorded as having produced the answers")
    ap.add_argument("--timeout", type=int, default=900)
    a = ap.parse_args()

    base = ROOT / "benchmarks" / "runs" / a.run_id
    arms = {c: base / f"{a.skill}.{c}" for c in ("with-skill", "baseline")}
    for c, d in arms.items():
        if not d.is_dir():
            sys.exit(f"missing arm: {d.relative_to(ROOT)} — run run_eval_arm.py --condition {c} first")

    evals = json.loads((skill_dir(a.skill) / "evals" / "evals.json").read_text())["evals"]
    gdir = base / f"{a.skill}.grading"
    gdir.mkdir(parents=True, exist_ok=True)

    verdicts = {c: [] for c in arms}
    for e in evals:
        files = {c: arms[c] / f"e{e['id']}.md" for c in arms}
        if not all(f.exists() for f in files.values()):
            print(f"  e{e['id']}: SKIP — missing a response in one arm")
            continue

        # Reproducible per-eval shuffle, not derivable from the eval number alone.
        seed = int(hashlib.sha256(f"{a.run_id}/{a.skill}/{e['id']}".encode()).hexdigest()[:8], 16)
        conds = ["with-skill", "baseline"]
        random.Random(seed).shuffle(conds)
        labels = dict(zip(["A", "B"], conds))          # label -> condition

        p = [GRADER_INSTRUCTIONS, f"=== REQUEST ===\n{e['prompt']}\n", "=== EXPECTATIONS ==="]
        p += [f"{i}. {x}" for i, x in enumerate(e["expectations"], 1)]
        p.append("")
        for lab, cond in labels.items():
            p.append(f"=== ANSWER {lab} ===\n{files[cond].read_text()}\n")

        gf = gdir / f"e{e['id']}.grader-prompt.txt"
        gf.write_text("\n".join(p))

        try:
            r = subprocess.run(["claude", "--model", a.grader_model, "--print"],
                               input="\n".join(p), capture_output=True, text=True, timeout=a.timeout)
            raw = r.stdout
        except subprocess.TimeoutExpired:
            print(f"  e{e['id']}: grader TIMEOUT")
            continue
        (gdir / f"e{e['id']}.grader-raw.txt").write_text(raw)

        m = re.search(r"\{.*\}", raw, re.S)
        if not m:
            print(f"  e{e['id']}: grader returned no JSON")
            continue
        try:
            scored = json.loads(m.group(0))
        except json.JSONDecodeError as exc:
            print(f"  e{e['id']}: unparseable grader JSON ({exc})")
            continue

        for lab, cond in labels.items():
            items = scored.get(lab) or []
            by_n = {int(i.get("n", k + 1)): i for k, i in enumerate(items)}
            verdicts[cond].append({
                "id": e["id"],
                "name": e.get("name", f"eval-{e['id']}"),
                "expectations": [
                    {"text": x,
                     "verdict": str(by_n.get(i, {}).get("verdict", "fail")).lower(),
                     "evidence": by_n.get(i, {}).get("evidence", "absent")}
                    for i, x in enumerate(e["expectations"], 1)
                ],
            })
        print(f"  e{e['id']}: graded ({len(e['expectations'])} expectations x 2 arms)")

    W = {"pass": 1.0, "partial": 0.5, "fail": 0.0}
    outdir = ROOT / "benchmarks" / "results"
    for cond, evs in verdicts.items():
        if not evs:
            continue
        doc = {"skill": a.skill, "model": a.model, "run": a.run_label,
               "condition": cond, "evals": evs}
        f = outdir / f"{a.skill}.{cond}.results.json"
        f.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
        earned = sum(W.get(x["verdict"], 0.0) for ev in evs for x in ev["expectations"])
        total = sum(len(ev["expectations"]) for ev in evs)
        print(f"  {cond:<11} {100*earned/total:5.1f}%  ({earned:g}/{total})  -> {f.relative_to(ROOT)}")

    print("\nNow run: python3 scripts/check-published-numbers.py")
    print("It will fail until the README and benchmarks/ tables match these verdicts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
