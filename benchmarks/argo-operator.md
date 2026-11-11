# argo-operator

## Not yet measured

**No baseline run exists for this skill.** The eval suite is written and committed
(11 evals), but it has not been run against an unaided baseline, so there is no
with-skill versus baseline delta to report.

This repository's bar is that a skill with no measured baseline is a guess. This file
exists so the skill is not silently absent from the benchmark set, and so the gap is
visible rather than implied by omission. Treat the skill as unproven until a run lands
here.

## What a first run needs

The evals cover operator-owned behavior, and are written to be answered when the fix is an operator input rather than the reconciled object. Every eval
assumes a live OpenShift GitOps instance, so a first run needs cluster access and, for
most evals, fixtures that actually exhibit the symptom described in the prompt.

| | |
|---|---|
| Evals | 11 |
| Suite location | `skills/gitops/argo-operator/evals/evals.json` |
| Fixtures | none committed yet — see `docs/adding-a-skill.md` §5 |
| Baseline | not run |

Until fixtures exist, evals whose prompts name objects that are not on the test cluster
will cap both arms at partial credit and measure nothing. That trap is documented in
`docs/adding-a-skill.md` §3 and applies directly here.
