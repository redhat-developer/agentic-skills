# argo-performance-tuning

## Run 9 — 2026-11-10, new two-arm harness

**94.9% with the skill vs 57.9% baseline (+36.9) over 107 expectations.**

> Generated with `make baseline` / `make with-skill` / `make grade` — see
> [methodology](README.md#how-to-produce-a-run). One blind grader scored both arms
> of each eval in a single call, every verdict carries a verbatim evidence quote,
> and the baseline ran from an empty directory so `skills/` was unreachable.
> **Not comparable to runs 1-8** — different harness, stricter grader.

| # | Eval | n | with-skill | baseline | delta |
|---|------|--:|-----------:|---------:|------:|
| 1 | Repo-server OOMKilled on monorepo mass sync | 8 | 100% | 44% | +56 |
| 2 | Sluggish UI and slow drift detection at scale | 6 | 100% | 58% | +42 |
| 3 | Single controller maxed out across many clusters | 6 | 92% | 67% | +25 |
| 4 | Context deadline exceeded viewing a large Application | 5 | 100% | 70% | +30 |
| 5 | Git provider rate-limiting across many apps on one repo | 4 | 88% | 0% | +88 |
| 6 | High baseline load without webhooks at scale | 5 | 100% | 70% | +30 |
| 7 | User requests the known Operator misconfiguration directly | 5 | 100% | 90% | +10 |
| 8 | Sharding requested with only one cluster | 4 | 100% | 88% | +12 |
| 9 | Floating tag freshness vs. cache TTL | 4 | 100% | 100% | +0 |
| 10 | Shallow clone on a public repo with no existing Secret | 4 | 100% | 0% | +100 |
| 11 | Unsupported sharding algorithm requested on OpenShift GitOps | 4 | 75% | 75% | +0 |
| 12 | Multiple simultaneous symptoms — prioritization | 6 | 83% | 50% | +33 |
| 13 | Safety model compliance on a direct apply request | 4 | 88% | 50% | +38 |
| 14 | Standalone Argo CD, not the OpenShift GitOps Operator | 5 | 100% | 100% | +0 |
| 15 | High controller CPU from child-resource status churn | 5 | 90% | 60% | +30 |
| 16 | High API load on managed clusters from non-GitOps resources | 6 | 100% | 50% | +50 |
| 17 | Monorepo commit invalidates cache for unrelated apps | 6 | 100% | 58% | +42 |
| 18 | Shard rebalancing without restarts requested | 5 | 100% | 50% | +50 |
| 19 | Controller slow calling managed cluster API, not repo-server | 5 | 90% | 70% | +20 |
| 20 | Large resource tree causing Redis traffic | 5 | 80% | 0% | +80 |
| 21 | Round-robin assumed to be risk-free | 5 | 100% | 70% | +30 |
| | **total** | **107** | **94.9%** | **57.9%** | **+36.9** |

---

<details>
<summary>Superseded: runs 1-8 (different harness)</summary>

## Run 7 — 2026-10-23, live cluster, blind A/B

**96.7% with the skill vs 64.0% baseline (+32.7) over 107 expectations.**

Measured against a live OpenShift cluster (OpenShift GitOps 1.21.3, Argo CD v3.4.5).
Graders saw "Condition A"/"Condition B" without knowing which was which and could not
read `skills/`. Partial credit; every verdict carries an evidence string. Raw verdicts:
[`results/argo-performance-tuning.with-skill.results.json`](results/argo-performance-tuning.with-skill.results.json) and
[`results/argo-performance-tuning.baseline.results.json`](results/argo-performance-tuning.baseline.results.json).

| # | Eval | n | with-skill | baseline | delta |
|---|------|--:|-----------:|---------:|------:|
| 1 | Repo-server OOMKilled on monorepo mass sync | 8 | 94% | 56% | +38 |
| 2 | Sluggish UI and slow drift detection at scale | 6 | 100% | 83% | +17 |
| 3 | Single controller maxed out across many clusters | 6 | 75% | 42% | +33 |
| 4 | Context deadline exceeded viewing a large Application | 5 | 100% | 90% | +10 |
| 5 | Git provider rate-limiting across many apps on one repo | 4 | 75% | 12% | +62 |
| 6 | High baseline load without webhooks at scale | 5 | 100% | 100% | +0 |
| 7 | User requests the known Operator misconfiguration directly | 5 | 100% | 90% | +10 |
| 8 | Sharding requested with only one cluster | 4 | 100% | 100% | +0 |
| 9 | Floating tag freshness vs. cache TTL | 4 | 100% | 100% | +0 |
| 10 | Shallow clone on a public repo with no existing Secret | 4 | 100% | 25% | +75 |
| 11 | Unsupported sharding algorithm requested on OpenShift GitOps | 4 | 100% | 62% | +38 |
| 12 | Multiple simultaneous symptoms — prioritization | 6 | 100% | 75% | +25 |
| 13 | Safety model compliance on a direct apply request | 4 | 100% | 62% | +38 |
| 14 | Standalone Argo CD, not the OpenShift GitOps Operator | 5 | 100% | 100% | +0 |
| 15 | High controller CPU from child-resource status churn | 5 | 100% | 40% | +60 |
| 16 | High API load on managed clusters from non-GitOps resources | 6 | 92% | 50% | +42 |
| 17 | Monorepo commit invalidates cache for unrelated apps | 6 | 100% | 50% | +50 |
| 18 | Shard rebalancing without restarts requested | 5 | 100% | 40% | +60 |
| 19 | Controller slow calling managed cluster API, not repo-server | 5 | 100% | 90% | +10 |
| 20 | Large resource tree causing Redis traffic | 5 | 100% | 10% | +90 |
| 21 | Round-robin assumed to be risk-free | 5 | 100% | 70% | +30 |
| | **total** | **107** | **96.7%** | **64.0%** | **+32.7** |

**Largest gains:** #20 Large resource tree causing Redis traffic (+90); #10 Shallow clone on a public repo with no existing Secret (+75); #5 Git provider rate-limiting across many apps on one repo (+62).

> **Baseline reused from run 1 and regraded.** The eval prompts were verified
> byte-identical between runs, and baselines never see `skills/`. See the grader-drift
> table in the [root README](../README.md#benchmarks) — absolute scores move with the
> grader, so read the direction, not the decimal.

---

<details>
<summary>Superseded: v0.2.0 (2026-10-14) — simulated outcomes, no live cluster</summary>

## v0.1.0 (2026-10-14)

**Methodology note:** evaluated via Cursor subagents rather than the `claude` CLI used by the
other benchmarks in this repo. For practicality, each (model, condition) pair was run as a
single subagent session handling all 14 scenarios as independent, non-cross-referencing prompts
(rather than 14 separate subagent spawns) — instructed explicitly not to let answers leak across
scenarios. Scoring was done by the orchestrating agent reading each full transcript against the
written `expectations` arrays in `evals/evals.json`. Models are Cursor's currently available
subagent slugs, labeled below by vendor-neutral tier name since they don't map 1:1 to this
repo's historical `claude-opus-4-6`/`claude-sonnet-4-6` naming.

### Opus-tier (`claude-4.6-opus-high-thinking`)

| Eval | With Skill | Baseline | Delta |
|------|-----------|----------|-------|
| 1. Repo-server OOMKilled on monorepo mass sync | 7/7 (100%) | 2/7 (29%) | +71% |
| 2. Sluggish UI / slow drift detection at scale | 6/6 (100%) | 4/6 (67%) | +33% |
| 3. Single controller maxed out across 20 clusters | 6/6 (100%) | 3/6 (50%) | +50% |
| 4. Context deadline exceeded on a large chart | 5/5 (100%) | 0/5 (0%) | **+100%** |
| 5. Git provider rate-limiting across 500 apps | 3/4 (75%) | 0/4 (0%) | +75% |
| 6. High baseline load without webhooks | 5/5 (100%) | 4/5 (80%) | +20% |
| 7. User requests the known Operator misconfiguration | 5/5 (100%) | 0/5 (0%) | **+100%** |
| 8. Sharding requested with only one cluster | 4/4 (100%) | 4/4 (100%) | 0% |
| 9. Floating tag freshness vs. cache TTL | 4/4 (100%) | 4/4 (100%) | 0% |
| 10. Shallow clone on public repo, no Secret yet | 4/4 (100%) | 1/4 (25%) | +75% |
| 11. Unsupported sharding algorithm requested | 4/4 (100%) | 2/4 (50%) | +50% |
| 12. Multiple simultaneous symptoms — prioritization | 5/5 (100%) | 2/5 (40%) | +60% |
| 13. Safety-model compliance on direct apply request | 4/4 (100%) | 2/4 (50%) | +50% |
| 14. Standalone Argo CD, not the Operator | 5/5 (100%) | 4/5 (80%) | +20% |
| **Overall** | **67/68 (99%)** | **32/68 (47%)** | **+52%** |

### Sonnet-tier (`claude-sonnet-5-thinking-xhigh`)

| Eval | With Skill | Baseline | Delta |
|------|-----------|----------|-------|
| 1. Repo-server OOMKilled on monorepo mass sync | 7/7 (100%) | 4/7 (57%) | +43% |
| 2. Sluggish UI / slow drift detection at scale | 6/6 (100%) | 3/6 (50%) | +50% |
| 3. Single controller maxed out across 20 clusters | 6/6 (100%) | 3/6 (50%) | +50% |
| 4. Context deadline exceeded on a large chart | 5/5 (100%) | 2/5 (40%) | +60% |
| 5. Git provider rate-limiting across 500 apps | 4/4 (100%) | 0/4 (0%) | **+100%** |
| 6. High baseline load without webhooks | 5/5 (100%) | 4/5 (80%) | +20% |
| 7. User requests the known Operator misconfiguration | 5/5 (100%) | 2/5 (40%) | +60% |
| 8. Sharding requested with only one cluster | 4/4 (100%) | 4/4 (100%) | 0% |
| 9. Floating tag freshness vs. cache TTL | 4/4 (100%) | 4/4 (100%) | 0% |
| 10. Shallow clone on public repo, no Secret yet | 4/4 (100%) | 0/4 (0%) | **+100%** |
| 11. Unsupported sharding algorithm requested | 4/4 (100%) | 3/4 (75%) | +25% |
| 12. Multiple simultaneous symptoms — prioritization | 5/5 (100%) | 3/5 (60%) | +40% |
| 13. Safety-model compliance on direct apply request | 4/4 (100%) | 2/4 (50%) | +50% |
| 14. Standalone Argo CD, not the Operator | 5/5 (100%) | 4/5 (80%) | +20% |
| **Overall** | **68/68 (100%)** | **38/68 (56%)** | **+44%** |

### Cross-Model Summary

| Model | With Skill | Baseline | Delta |
|-------|-----------|----------|-------|
| Opus-tier | 99% | 47% | +52% |
| Sonnet-tier | 100% | 56% | +44% |

**Key findings:**

- **Both models are effectively perfect with the skill loaded** (99–100%). The one Opus miss
  (eval 5) was a minor omission — it recommended the right setting and value but didn't
  explicitly contrast it against `ARGOCD_REPO_SERVER_PARALLELISM_LIMIT`, which the Sonnet run
  did.
- **Eval 7 (Operator misconfiguration) is the clearest demonstration of value.** The prompt
  directly asks the agent to put `controller.status.processors`/`controller.operation.processors`
  under `spec.extraConfig` — the exact mistake this skill's reference calls out by name. Baseline
  Opus **validated the user's broken request outright** ("This is a reasonable and well-targeted
  request") and generated the non-functional patch as asked — 0/5, the single most concerning
  baseline result in the set, since nothing in the baseline's own response would have alerted the
  user that their change silently does nothing. Baseline Sonnet sensed something was wrong and
  pushed back, but "corrected" it to a different, also-incorrect location (`spec.controller.env`
  with invented env var names `ARGOCD_CONTROLLER_STATUS_PROCESSORS`/`_OPERATION_PROCESSORS` that
  don't exist in Argo CD) — 2/5. Both skill-equipped runs caught the mistake and produced the
  real fix (`spec.controller.processors.status`/`.operation`) — 5/5 each.
- **Eval 5 and eval 10 are near-total baseline blind spots on both models** (0/4 on three of the
  four baseline/model combinations). Neither model's unaided knowledge included
  `ARGOCD_GIT_LS_REMOTE_PARALLELISM_LIMIT` (eval 5) or the repository Secret `depth` field for
  shallow cloning (eval 10) — baseline Sonnet explicitly and honestly declined to invent a field
  name for the latter ("I don't want to invent a key name that doesn't exist"), which is good
  epistemic behavior but still produced zero practical help. Baseline Opus, by contrast,
  **hallucinated a plausible but nonexistent field name** (`fetchDepth` instead of `depth`) —
  worse than admitting uncertainty, since a user could apply it and have it silently not work.
- **Eval 4 (timeout alignment) is a strong Opus-specific gap** (0/5 baseline) — Opus baseline
  conflated the `argocd-server`→repo-server timeout with a generic ingress/Route timeout and
  never named `ARGOCD_APPLICATION_CONTROLLER_REPO_SERVER_TIMEOUT_SECONDS` at all, missing the
  three-timeout chain entirely.
- **Evals 8 and 9 show zero delta on both models** — "sharding needs >1 cluster" and "cache TTL
  isn't an image-freshness knob" are derivable from general GitOps/caching reasoning without
  Argo-specific knowledge, and both baselines got there unaided. These are useful as a sanity
  check that the skill isn't just winning by default — the delta is concentrated exactly where
  specialized, version-specific knowledge is actually required.
- **Baseline sharding-algorithm guidance (eval 11) is where baseline models actively disagree
  with the skill's recommendation**, not just omit detail: both baselines recommended
  `consistent-hashing` as the preferred choice for OpenShift GitOps without the
  not-officially-supported caveat (Opus baseline even argued affirmatively for it), where the
  skill recommends `round-robin` specifically because of that support gap.
- **Sonnet-tier baseline modestly outperforms Opus-tier baseline overall** (56% vs. 47%) in this
  run — driven mostly by Sonnet's more cautious hedging on uncertain settings (it says "I'm not
  sure" rather than inventing specifics in several places) versus Opus baseline's tendency to
  state incorrect specifics confidently (the `extraConfig` validation in eval 7, the `fetchDepth`
  field in eval 10, the pro-`consistent-hashing` stance in eval 11). With the skill loaded, this
  gap disappears entirely.


</details>

</details>
