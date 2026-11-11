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
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Read-only cluster verbs. Deliberately an allowlist, not --dangerously-skip-permissions:
# an eval run is not a reason to hand an agent write access to a live cluster.
# Allow the binaries, then deny the mutating verbs. An earlier version listed
# "Bash(oc get:*)" and friends, but these patterns match by literal prefix, so
# `oc -n openshift-gitops get pods` — the form anyone actually types — did not
# match and was refused. That silently handicapped both arms on ~1-2 evals each.
# Denying verbs is the only formulation that permits a read wherever the flags
# happen to sit while still keeping writes out.
CLUSTER_TOOLS = ["Bash(oc:*)", "Bash(kubectl:*)"]
CLUSTER_DENY = [
    "Bash(oc delete:*)", "Bash(oc apply:*)", "Bash(oc patch:*)", "Bash(oc create:*)",
    "Bash(oc edit:*)", "Bash(oc replace:*)", "Bash(oc scale:*)", "Bash(oc annotate:*)",
    "Bash(oc label:*)", "Bash(oc set:*)", "Bash(oc rollout:*)", "Bash(oc cp:*)",
    "Bash(oc exec:*)", "Bash(oc adm:*)",
    "Bash(kubectl delete:*)", "Bash(kubectl apply:*)", "Bash(kubectl patch:*)",
    "Bash(kubectl create:*)", "Bash(kubectl edit:*)", "Bash(kubectl replace:*)",
    "Bash(kubectl scale:*)", "Bash(kubectl annotate:*)", "Bash(kubectl label:*)",
    "Bash(kubectl set:*)", "Bash(kubectl rollout:*)", "Bash(kubectl cp:*)",
    "Bash(kubectl exec:*)",
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
    ap.add_argument("--fixtures", default="",
                    help="comma-separated repo-relative paths both arms must be able to read "
                         "(e.g. 'tests'). Symlinked into the baseline's scratch dir so it can "
                         "reach the material under audit WITHOUT reaching skills/.")
    ap.add_argument("--only", help="comma-separated eval ids, for re-running a subset")
    ap.add_argument("--require-state", default="",
                    help="assert cluster state before running, as "
                         "'<kind>/<ns>/<name>=<jsonpath>:<expected>' (repeatable, comma-separated). "
                         "Aborts if it does not match. An eval graded against a fixture that "
                         "silently drifted is worse than no eval.")
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

    fixtures = [p for p in a.fixtures.split(",") if p]
    tools = list(CLUSTER_TOOLS) if a.cluster else []
    if a.condition == "with-skill":
        tools += SKILL_TOOLS
        frame, cwd = skill_frame(sd), str(ROOT)
        scratch = None
    else:
        # Baseline runs from a scratch directory. Isolation is structural: skills/ is
        # simply not there. But anything the eval asks the agent to *examine* must be,
        # or the delta measures missing files rather than missing knowledge — the
        # published repo-audit run gave both arms identical fixture access for exactly
        # this reason.
        scratch = tempfile.mkdtemp(prefix="eval-baseline-")
        for rel in fixtures:
            src = (ROOT / rel).resolve()
            if not src.exists():
                sys.exit(f"--fixtures path does not exist: {rel}")
            dst = pathlib.Path(scratch) / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            # COPY, never symlink. A symlink pointing outside the agent's working
            # directory is refused by the sandbox, and the failure is silent from the
            # harness's point of view: the run completes, the response looks like prose,
            # and the arm scores near zero because it never saw a single file. That
            # produced a 58.2% baseline against a published 79.4% before it was caught.
            if src.is_dir():
                shutil.copytree(src, dst, symlinks=False, dirs_exist_ok=True)
            else:
                shutil.copy2(src, dst)
        if fixtures:
            tools += SKILL_TOOLS  # Read/Glob/Grep, so it can actually open them
        frame, cwd = BASELINE_FRAME, scratch

    # Fixture-state assertion. A cluster eval whose fixture has drifted still runs,
    # still produces confident prose, and still gets graded — and the two arms can
    # even see DIFFERENT states if anything touches the cluster between them, which
    # silently invalidates the comparison rather than failing it. Check first.
    for spec in [s for s in a.require_state.split(",") if s]:
        try:
            target, want = spec.rsplit(":", 1)
            res, jp = target.split("=", 1)
        except ValueError:
            sys.exit(f"--require-state malformed: {spec!r}")
        kind, ns, name = res.split("/", 2)
        kc = "oc" if subprocess.run(["which", "oc"], capture_output=True).returncode == 0 else "kubectl"
        got = subprocess.run([kc, "get", kind, name, "-n", ns, "-o", f"jsonpath={jp}"],
                             capture_output=True, text=True).stdout.strip()
        if got != want:
            sys.exit(f"  FIXTURE CHECK FAILED: {kind}/{ns}/{name} {jp} is {got!r}, expected {want!r}.\n"
                     f"  Re-arm the fixture (tests/argo-cluster-debug/fixtures/setup.sh) and make sure\n"
                     f"  nothing else is touching the cluster, then re-run.")
        print(f"  fixture ok: {kind}/{ns}/{name} {jp} == {want}")

    print(f"{a.skill} / {a.condition} / {a.model}: {len(evals)} evals -> {out.relative_to(ROOT)}")
    if scratch:
        print(f"  baseline cwd: {scratch} (skills/ unreachable; fixtures: {fixtures or 'none'})")

    # Pre-flight: can the AGENT read the fixtures from where it will run?
    # A filesystem check is not sufficient — a symlink out of the sandbox passes
    # os.path checks and is still refused at read time, which fails silently: the
    # arm completes, the prose looks fine, and every score is near zero.
    if fixtures:
        probe = (f"List the files under {fixtures[0]}/ and reply with ONLY the integer "
                 f"count of regular files you can actually read. No prose.")
        try:
            pr = subprocess.run(["claude", "--model", a.model, "--print",
                                 "--allowedTools", *SKILL_TOOLS],
                                input=probe, cwd=cwd, capture_output=True,
                                text=True, timeout=180)
            m = re.search(r"\d+", pr.stdout or "")
            seen = int(m.group(0)) if m else 0
        except Exception:
            seen = 0
        on_disk = sum(1 for _ in (pathlib.Path(cwd) / fixtures[0]).rglob("*") if _.is_file())
        if seen == 0:
            sys.exit(f"  PRE-FLIGHT FAILED: agent read 0 files under {fixtures[0]}/ "
                     f"({on_disk} present on disk at {cwd}). Aborting rather than "
                     f"generating an arm that scores near zero for the wrong reason.")
        print(f"  pre-flight: agent reached {seen} file(s) under {fixtures[0]}/ "
              f"({on_disk} on disk)")

    for e in evals:
        f = out / f"e{e['id']}.md"
        if f.exists() and f.stat().st_size > 100:
            print(f"  e{e['id']}: skip (exists)")
            continue
        cmd = ["claude", "--model", a.model, "--print"]
        if tools:
            cmd += ["--allowedTools", *tools]
        if a.cluster:
            cmd += ["--disallowedTools", *CLUSTER_DENY]
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
