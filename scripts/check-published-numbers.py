#!/usr/bin/env python3
"""Fail if any published score disagrees with benchmarks/results/.

Scores are written in four places — the root README table, benchmarks/README.md,
each benchmarks/<skill>.md, and the result JSON itself. They have drifted apart
repeatedly: a re-run would update one or two and leave the rest showing numbers
that were correct a run ago. A stale benchmark is worse than no benchmark,
because it still looks authoritative.

This recomputes every score from the verdict files and checks each published
figure against it.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESULTS = ROOT / "benchmarks" / "results"
WEIGHT = {"pass": 1.0, "partial": 0.5, "fail": 0.0}
TOL = 0.06  # scores are printed to 1dp; .05 is an exact tie on half-way values


def score(skill, condition):
    f = RESULTS / f"{skill}.{condition}.results.json"
    d = json.loads(f.read_text())
    earned = total = 0.0
    for ev in d["evals"]:
        for x in ev["expectations"]:
            earned += WEIGHT.get(str(x.get("verdict", "fail")).lower(), 0.0)
            total += 1.0
    return (100 * earned / total if total else 0.0), int(total)


def main():
    skills = sorted({f.name.split(".")[0] for f in RESULTS.glob("*.results.json")})
    if not skills:
        print("no results to check", file=sys.stderr)
        return 1

    truth, tw, tb, tn = {}, 0.0, 0.0, 0
    for s in skills:
        w, n = score(s, "with-skill")
        b, _ = score(s, "baseline")
        truth[s] = (w, b, n)
        tw += w * n
        tb += b * n
        tn += n
    overall = (tw / tn, tb / tn)

    problems = []

    def check(where, label, got, want):
        if abs(got - want) > TOL:
            problems.append(f"{where}: {label} shows {got}, results say {want:.1f}")

    # root README table
    readme = (ROOT / "README.md").read_text()
    for s, (w, b, _) in truth.items():
        row = next((l for l in readme.splitlines() if f"[`{s}`]" in l), None)
        if not row:
            problems.append(f"README.md: no row for {s}")
            continue
        m = re.search(r"\|\s*\**([\d.]+)%\**\s*\|\s*\**([\d.]+)%\**", row)
        if not m:
            problems.append(f"README.md: no row for {s}")
            continue
        check("README.md", f"{s} with-skill", float(m.group(1)), w)
        check("README.md", f"{s} baseline", float(m.group(2)), b)
    m = re.search(r"\*\*Weighted overall\*\*\s*\|\s*\*\*([\d.]+)%\*\*\s*\|\s*\*\*([\d.]+)%\*\*", readme)
    if m:
        check("README.md", "weighted with-skill", float(m.group(1)), overall[0])
        check("README.md", "weighted baseline", float(m.group(2)), overall[1])
    else:
        problems.append("README.md: weighted overall row not found")

    # benchmarks/README.md table
    bench = (ROOT / "benchmarks" / "README.md").read_text()
    for s, (w, b, _) in truth.items():
        row = next((l for l in bench.splitlines() if f"`{s}`" in l), None)
        if not row:
            problems.append(f"benchmarks/README.md: no row for {s}")
            continue
        m = re.search(r"\|\s*\**([\d.]+)%\**\s*\|\s*\**?([\d.]+)%", row)
        if not m:
            problems.append(f"benchmarks/README.md: no row for {s}")
            continue
        check("benchmarks/README.md", f"{s} with-skill", float(m.group(1)), w)
        check("benchmarks/README.md", f"{s} baseline", float(m.group(2)), b)

    # per-skill docs
    for s, (w, b, n) in truth.items():
        f = ROOT / "benchmarks" / f"{s}.md"
        if not f.exists():
            problems.append(f"benchmarks/{s}.md: missing")
            continue
        m = re.search(r"\*\*([\d.]+)% with the skill vs ([\d.]+)% baseline \(([+\-][\d.]+)\) over (\d+)",
                      f.read_text())
        if not m:
            problems.append(f"benchmarks/{s}.md: headline score line not found")
            continue
        check(f"benchmarks/{s}.md", "with-skill", float(m.group(1)), w)
        check(f"benchmarks/{s}.md", "baseline", float(m.group(2)), b)
        check(f"benchmarks/{s}.md", "delta", float(m.group(3)), w - b)
        if int(m.group(4)) != n:
            problems.append(f"benchmarks/{s}.md: says {m.group(4)} expectations, results have {n}")

    if problems:
        print("Published numbers disagree with benchmarks/results/:", file=sys.stderr)
        for p in problems:
            print("   ", p, file=sys.stderr)
        print("\nRe-read the verdict files and update the docs, or re-record the run.",
              file=sys.stderr)
        return 1

    print(f"published numbers match benchmarks/results/ "
          f"({len(skills)} skills, {tn} expectations, weighted "
          f"{overall[0]:.1f}%/{overall[1]:.1f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
