# Benchmarks — methodology and caveats

> **Mid-migration.** `argo-operations` and `argo-team-onboard` were removed; their
> pages are archived as `archive-*.md`. `argo-cluster-debug` absorbed Argo Rollouts
> runtime control (+19 expectations) so its published verdict no longer applies and is
> withdrawn rather than carried forward. `argo-knowledge` is pending a narrowing.
> `argo-performance-tuning` and `argo-repo-audit` are unchanged in scope and their
> run-7 numbers stand. No weighted overall until every row is re-measured.

Measured 2026-10-23 (run 7) against a live OpenShift cluster (OpenShift GitOps 1.21.3, Argo CD
v3.4.5). **324 expectations per condition across the three unchanged skills, graded twice — once with the skills, once
without.** 1,174 verdicts, each carrying an evidence string, in [`results/`](results/).

| Skill | with-skill | baseline | delta | per-eval detail |
|-------|-----------:|---------:|------:|---|
| `argo-performance-tuning` | **96.7%** | 64.0% | **+32.7** | [↗](argo-performance-tuning.md) |
| `argo-repo-audit` | **95.3%** | 79.4% | **+15.9** | [↗](argo-repo-audit.md) |
| `argo-cluster-debug` | — | — | — | **withdrawn** — scope changed, [↗](argo-cluster-debug.md) |
| `argo-knowledge` | — | — | — | **withdrawn** — scope changed, [↗](argo-knowledge.md) |
| **Weighted overall** | **96.1%** | **70.8%** | **+25.3** | **2 of 4 skills, n=192** — excludes `argo-cluster-debug` and `argo-knowledge` |

**What run 7 actually re-measured.** Only `argo-cluster-debug` was re-run end to end
(new fixtures for evals 2, 4 and 6), and only `argo-performance-tuning` was re-graded
(eval 16 gained an expectation). The other four rows carry forward unchanged verdicts
against unchanged expectation suites — they are current-suite results, not stale ones,
which is why `make history` reports no fingerprint drift. `benchmarks/history.jsonl`
records a run-7 row for all six so the snapshot is complete; four of those rows are
identical to run 6 by construction, not by re-measurement.

## Method

- **Blind A/B.** Graders saw "Condition A" and "Condition B" with a seeded flip, were
  never told which was which, and could not read `skills/`. Flips came out mixed.
- **Per expectation, not per eval**, with partial credit and a required evidence string.
- **Strong baselines, deliberately.** Each baseline agent was an experienced OpenShift
  GitOps engineer with the same prompts, CLIs, live cluster and read-only limits — just
  no `skills/`. A hobbled baseline produces a flattering number and tells you nothing.
  Several baselines beat their with-skill counterpart on specific items.
- **Integrity-checked before publication:** every expectation graded exactly once, every
  verdict's text joined verbatim against the eval definition, every blind input
  md5-verified complete against its source. Run 1 shipped a truncated input; that last
  check exists because of it.
- **Reproduce:** `make score` · `make score-compare PRIOR=results-run1-2026-10-20`.

## How much of this is grader noise? We measured it.

Four baselines were reused unchanged from run 1 and regraded by a fresh grader. Same
answer text, same expectations — so any difference is the grader, not the skill:

| Reused baseline | n | grader agreement | drift |
|---|--:|--:|--:|
| `argo-knowledge` | 131 | 98% | −0.8 |
| `argo-performance-tuning` | 101 | 92% | −2.0 |
| `argo-cluster-debug` | 57 | 88% | +0.9 |
| `argo-repo-audit` | 80 | 86% | **−6.9** |
| **pooled** | **369** | **92%** | — |

Disagreements are almost entirely one-directional (`pass` → `partial`): the second grader
is stricter at that boundary, not randomly different. Two consequences, both cutting
against the headline numbers:

1. **Absolute scores are not comparable across grading passes.** A score can move ~7
   points with no change to the skill at all.
2. **A stricter grader *widens* deltas when the with-skill arm is near ceiling.**
   `argo-repo-audit` was the clean case: its with-skill score was 97.5% in two successive
   runs, but the regraded baseline fell 88.1% → 81.2%, so the delta grew +9.4 → +16.2
   without the skill improving.

That skill is also the clearest case of the opposite effect. Its expectations were later
rewritten because they could not distinguish a correct root cause from a confident wrong
one, and under the corrected rubric the baseline recovered to 85.4% and the delta settled
at **+11.6** — inside the +9 to +16 band predicted above, and *lower* than the figure the
vaguer suite had produced. Improving your own measuring instrument should be free to move
the number down, and here it did.

Within a run both conditions share one grader and one bar, so **direction and
rank-ordering** are the trustworthy part. Treat anything under ~5 points as
indistinguishable from zero.

## Run-to-run variance: we measured that too, and it is larger than the grader's

The section above measures the GRADER. This measures the whole pipeline — new agent
runs, new grader pass, everything held otherwise constant.

`argo-cluster-debug` was run twice in succession against the **same expectation suite**
(`suite_fp 21e0bc90372b`), the **same cluster**, and the **same deployed fixtures**. The
only difference was six words removed from one prompt, affecting 6 of 61 expectations.

| run | with-skill | baseline | delta |
|---|---:|---:|---:|
| 7 | 97.5% | 92.6% | **+4.9** |
| 8 | 99.2% | 89.3% | **+9.8** |

**The delta doubled.** One prompt tweak cannot move an aggregate over 61 expectations by
five points; what moved was the agents and the grader. Most of it is the baseline, which
scored 92.6% then 89.3% — the second baseline simply ran fewer checks. Across four runs
of this suite the baseline spans 84.7%–92.6%.

Three consequences, all of which cut against reading any single row of this page too
confidently:

1. **A single run's delta is not a point estimate.** For this suite it is worth roughly
   ±5 points. Published numbers are the most recent run, not a mean, because we do not
   have enough runs per suite to report one honestly.
2. **Direction is far more robust than magnitude.** `argo-cluster-debug` has been
   positive in every run that used a correctness-discriminating suite (+9.4, +6.6, +4.9,
   +9.8). "This helps" is supported; "this helps by N points" is not.
3. **Earlier conclusions drawn from one run were overconfident, including ours.** Run 7
   put this skill below the ~5-point floor and the previous revision of this page said
   so. Run 8 put it at +9.8. Neither number alone was worth the sentence written around
   it.

The honest summary for `argo-cluster-debug` is **consistently positive, magnitude
somewhere around +5 to +10, not resolved further by the data we have.**

## What the numbers say

**The delta tracks how product-specific the skill is.** Performance tuning gains most —
the baseline there was confidently wrong rather than vague: it called an experimental
sharding algorithm "GA, supported… the sane default", never named
`ARGOCD_APPLICATION_TREE_SHARD_SIZE` for a resource-tree problem, and applied patches
with no dry-run and no confirmation. The lesson: *encode what is version- and
product-specific; do not re-encode what the model already knows.*

**`argo-operations` went from −3.6 to +9.4.** Run 1 lost to its own baseline on one
category — no post-action verification. The skill stopped at the confirmation gate and
never said "now check it worked". Adding a Step 4: Verify closed it; all four failing
expectations flipped to pass. Roughly a third of the swing is that fix, the rest a
baseline that is no longer contaminated.

**Two skills tie their baselines** — `argo-team-onboard` (87/103 each) and
`argo-cluster-debug` (52.5/57 each). They split rather than dominate: the skill arm
reliably ends at a "commit this?" Git gate and honors "don't re-create what exists",
while the baseline writes more complete literal YAML.

## The cluster-debug re-run, and what it exposed about the evals

Four `argo-cluster-debug` scenarios named resources that did not exist on the cluster,
capping both arms. We deployed real fixtures — an Application driven OutOfSync *and*
Degraded by live image drift with `selfHeal: false`, a paused blue-green Rollout
reporting health `Suspended`, a multi-source Application failing with
`ComparisonError: failed to generate manifest for source 1 of 2` — re-ran both arms, and
tore the fixtures down. Both rose ~4 points (87.7→92.1, 88.6→92.1), matching the
predicted headroom. **The gap did not move.**

That re-run exposed a limitation in the evals themselves. On the two scenarios where the
arms reached *different* root causes, the skill arm was right both times and the baseline
wrong both times — and they scored **identically**:

| eval | with-skill | baseline | verified truth |
|---|---|---|---|
| 3 | zero-length conversion-webhook `caBundle` | "the operator pod is down" | `caBundle` length **0**; operator pods all **1/1 Running**; InstallPlan `install-fzm4w` Failed on exactly that webhook |
| 8 | `CrashLoopBackOff` from a probe/port mismatch | "the pause landed mid-bringup" | pod **CrashLoopBackOff, 13 restarts**; `containerPort: 80` while the image binds **:8443** |

Expectations phrased "identifies the root cause" are satisfied by naming a *plausible*
cause, not the *correct* one. Until they discriminate on correctness, this suite cannot
resolve the difference it exists to measure. **Read `0.0` as "not resolved by this
instrument", not "no difference".** This is the next change to the suite.

## The suite changed after these numbers were measured

The `argo-cluster-debug` expectations were rewritten after run 3 to test whether a
stated root cause is **correct and grounded**, not merely plausible — the limitation
described above. Expectations that said "produces a report with root cause and
recommendations" now add: *every root cause asserted must be backed by the specific
observation that establishes it, and a cause contradicted by output shown elsewhere in
the same answer fails even if it is plausible and well written.* Evals 3 and 8 also
gained expectations naming the specific finding each must land.

The rewrite was validated rather than assumed. Re-grading the **same two stored
answers** from run 3 blind, against old and new expectations:

| | with-skill | baseline | gap |
|---|---:|---:|---:|
| old expectations | 96.2% | 96.2% | **+0.0** |
| new expectations | 100.0% | 86.7% | **+13.3** |

The old wording scored a correct diagnosis and a factually wrong one identically. The
new wording separates them, in the direction the independently verified cluster state
supports. The baseline lost exactly where it should: it explained `Available=False` by
asserting a Service-selector problem with no output shown, while the other answer showed
the pod in `CrashLoopBackOff` with zero Service endpoints.

**That caveat has since been discharged.** As of run 6 (2026-10-23) every row on this
page is graded against the suite currently on disk — `make history` reports no stale
fingerprints — so the numbers in the table above are internally comparable.

Getting there required the same correction on three more suites, found the same way: by
reading what the graded runs actually rewarded rather than re-reading the expectations
on their own.

| Suite | Defect | Effect on the published delta |
|---|---|---|
| `argo-repo-audit` (9 of 12 evals) | Generic expectations satisfied by any plausible cause; one asserted the wrong Argo Rollouts `failureCondition` semantics | +16.2 → **+11.6** |
| `argo-performance-tuning` (eval 16) | Required `resource.exclusions` in `spec.extraConfig`, but the CRD has a dedicated `spec.resourceExclusions` and `extraConfig` *overrides* it — both arms used the correct field and both were capped | +27.4 → **+31.6** |
| `argo-team-onboard` (eval 13) | Prompt asserts Argo CD is absent; it is installed, and both arms proved it. Three of five expectations were unsatisfiable by a truthful answer | +0.0 → **+4.8** |

Note the directions. Two deltas went up and one went down — `argo-repo-audit` fell
because the sharper wording credited baseline work the vague wording had been failing.
A rubric correction that only ever flatters the skill is a rubric correction worth
distrusting.

## Caveats — read these before quoting the numbers

1. **Five of six baselines were generated fresh.** Only `argo-knowledge` carries a
   reused baseline, from run 2, because its suite did not change. Reuse is
   sound — baselines never see `skills/`, and prompts were verified byte-identical — but
   the grader drift quantified above applies to it.
2. **Run 1's two contaminated baselines are fixed.** To protect a live cluster, the
   `argo-operations` and `argo-team-onboard` baselines had been told to stop before
   writing — which is part of what those evals measure. Every run since states the write
   ban purely as an environment constraint.
3. **Three suites were re-graded, not re-run, after their expectations were corrected.**
   The agent answers were unchanged, so only the 11 affected evals were re-graded from
   the stored transcripts, with the A/B letters re-randomised independently. Re-grading
   the untouched evals too would have layered fresh grader variance on top of the rubric
   change and made the two indistinguishable. Unchanged evals carry their original
   verdicts byte-for-byte; this is checked mechanically before anything is published.
4. **Fixture coverage changes the answer, so track it.** Run 7 added fixtures for
   `argo-cluster-debug` evals 2, 4 and 6, and set the `maxUpdate` field eval 5 asks
   about. Giving both arms real objects raised the baseline more than the skill and cut
   that delta from +6.6 to +4.9. Any score for this suite is only meaningful alongside
   which fixtures were deployed; see
   [`argo-cluster-debug.md`](argo-cluster-debug.md) for the per-run record. One known
   artefact remains: eval 6's prompt says "for an hour" while the fixture is minutes
   old.
5. **Fixes made in response to a run are not reflected in it.** Each skill's files were
   verified unchanged during its own run, but defects the run surfaced — notably two
   `argo-repo-audit` credential/TLS scans that returned zero on their own fixtures — were
   fixed afterward. Those numbers describe the pre-fix skill.
6. **Single run, single model, no confidence intervals.** With the measured grader
   variance, treat small deltas as unresolved rather than real. On this page that is
   **half the suite**: `argo-cluster-debug` (+4.9), `argo-team-onboard` (+4.8) and
   `argo-knowledge` (+4.5) are not claimed as wins.

## Run history

`benchmarks/history.jsonl` is the append-only record of every scored run. Each row
carries a **`suite_fp`** — a hash of the exact expectation texts that were graded,
taken from the stored verdicts rather than from the current `evals.json`.

That field answers the question directory names could not: *is this score comparable
to that one?* Two scores are comparable **only** if their `suite_fp` match. Five of the
six suites have been reworded at some point, so comparing numbers without checking is
wrong more often than it is right.

```sh
make history        # the table, with stale suites flagged
make history-check  # fails if a result file was never recorded (also runs in CI)
```

Known wrinkle: the archived `argo-repo-audit` verdicts were mechanically edited when a
test-fixture credential literal was redacted. No verdict changed, but their `suite_fp`
now reflects the post-redaction text, so it matches the current suite for a reason
unrelated to grading.

## Archived runs

| Directory | What it holds |
|---|---|
| [`results/`](results/) | Current verdicts for the two skills whose scope did not change (run 6/7) |
| [`results-run1-2026-10-20/`](results-run1-2026-10-20/) | Run-1,174 verdicts — makes the grader-drift table reproducible |
| [`results-archive/`](results-archive/) | Verdicts for removed or scope-changed skills — historical, not current |
| [`results-run2-fixturecapped/`](results-run2-fixturecapped/) | `argo-cluster-debug` run 2, before fixtures were deployed |

Cluster-dependent suites need a real cluster — run them locally with `make eval-*`; CI
can only run the two that do not.
