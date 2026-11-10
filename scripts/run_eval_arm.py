#!/usr/bin/env python3
"""Generate one arm of a benchmark run: every eval for one skill, one condition, one model.

Two arms make a comparison:

    with-skill   the agent is told to read SKILL.md and its references first
    baseline     the agent answers as an experienced OpenShift GitOps engineer
                 with no access to skills/ at all

Why the baseline is framed that way: a hobbled baseline produces a flattering
delta and tells you nothing. benchmarks/README.md commits to a strong baseline,
so the baseline arm gets the same role framing and the same tools as the
with-skill arm — the *only* difference is whether the skill is available.

Isolation is structural, not instructional. Baseline runs execute from a scratch
directory containing nothing, so "do not read skills/" is not a rule the agent
could quietly break; the files are not there.

    scripts/run_eval_arm.py --skill argo-knowledge --condition baseline
    scripts/run_eval_arm.py --skill argo-cluster-debug --condition with-skill --cluster

Writes responses to benchmarks/runs/<run-id>/<skill>.<condition>/e<N>.md.
Grade them with scripts/grade_eval.py, which pairs the two arms and scores them
blind. This script never produces a verdict — generation and grading are kept
apart so one grader can see both arms without knowing which is which.
"""
from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Read-only cluster verbs. Deliberately an allowlist, not --dangerously-skip-permissions:
# an eval run is not a reason to hand an agent write access to a live cluster.
CLUSTER_TOOLS = [
    "Bash(oc get:*)", "Bash(oc describe:*)", "Bash(oc logs:*)",
    "Bash(oc api-resources:*)", "Bash(oc version:*)", "Bash(oc whoami:*)",
    "Bash(kubectl get:*)", "Bash(kubectl describe:*)", "Bash(kubectl logs:*)",
    "Bash(kubectl api-resources:*)", "Bash(kubectl version:*)",
]
SKILL_TOOLS = ["Read", "Glob", "Grep"]

BASELINE_FRAME = (
    "You are an experienced Red Hat OpenShift GitOps engineer. Answer from your own "
    "knowledge and from the cluster if you have access to one. There are no skill "
    "files, reference documents or repository notes available to you — do not look "
    "for any."
)


def skill_dir(skill: str) -> pathlib.Path:
    hits = sorted(ROOT.glob(f"skills/*/{skill}"))
    if not hits:
        sys.exit(f"no skill directory found for {skill!r} under skills/*/")
    return hits[0]


def skill_frame(sd: pathlib.Path) -> str:
    rel = sd.relative_to(ROOT)
    return (
        f"You are an experienced Red Hat OpenShift GitOps engineer with access to the "
        f"'{sd.name}' skill. Read {rel}/SKILL.md first, then load whichever files under "
        f"{rel}/references/ its routing table points at for this request. Follow the "
        f"skill's workflow."
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skill", required=True)
    ap.add_argument("--condition", required=True, choices=["with-skill", "baseline"])
    ap.add_argument("--model", default="claude-opus-5")
    ap.add_argument("--run-id", default=dt.date.today().isoformat())
    ap.add_argument("--cluster", action="store_true",
                    help="grant read-only oc/kubectl access to both arms")
    ap.add_argument("--only", help="comma-separated eval ids, for re-running a subset")
    ap.add_argument("--timeout", type=int, default=900)
    a = ap.parse_args()

    sd = skill_dir(a.skill)
    evals = json.loads((sd / "evals" / "evals.json").read_text())["evals"]
    if a.only:
        want = {int(x) for x in a.only.split(",")}
        evals = [e for e in evals if e["id"] in want]
        if not evals:
            sys.exit(f"--only {a.only} matched no evals")

    out = ROOT / "benchmarks" / "runs" / a.run_id / f"{a.skill}.{a.condition}"
    out.mkdir(parents=True, exist_ok=True)

    tools = list(CLUSTER_TOOLS) if a.cluster else []
    if a.condition == "with-skill":
        tools += SKILL_TOOLS
        frame, cwd = skill_frame(sd), str(ROOT)
        scratch = None
    else:
        # Baseline runs from an empty directory: isolation by construction.
        scratch = tempfile.mkdtemp(prefix="eval-baseline-")
        frame, cwd = BASELINE_FRAME, scratch

    print(f"{a.skill} / {a.condition} / {a.model}: {len(evals)} evals -> {out.relative_to(ROOT)}")
    if scratch:
        print(f"  baseline cwd: {scratch} (empty — skills/ is not reachable)")

    for e in evals:
        f = out / f"e{e['id']}.md"
        if f.exists() and f.stat().st_size > 100:
            print(f"  e{e['id']}: skip (exists)")
            continue
        cmd = ["claude", "--model", a.model, "--print"]
        if tools:
            cmd += ["--allowedTools", *tools]
        try:
            r = subprocess.run(cmd, input=f"{frame}\n\n{e['prompt']}\n", cwd=cwd,
                               capture_output=True, text=True, timeout=a.timeout)
            f.write_text(r.stdout if r.stdout.strip() else f"[no output]\n{r.stderr}")
        except subprocess.TimeoutExpired:
            f.write_text("[timeout]\n")
        print(f"  e{e['id']}: {f.stat().st_size} bytes")

    meta = out / "arm.json"
    meta.write_text(json.dumps(
        {"skill": a.skill, "condition": a.condition, "model": a.model,
         "run_id": a.run_id, "cluster_access": a.cluster,
         "eval_ids": [e["id"] for e in evals]}, indent=1) + "\n")
    print(f"  wrote {meta.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
