# argo-team-onboard

> **ARCHIVED.** `argo-team-onboard` was removed from this repo. On OpenShift the GitOps
> Operator owns installing, configuring and upgrading Argo CD, and desired state
> belongs in Git rather than being applied by an agent — which removed this skill's
> reason to exist. The numbers below are a historical record of a skill that no
> longer ships. They are not a claim about the current repo.


## Run 6 — 2026-10-23, live cluster, blind A/B

**89.4% with the skill vs 84.6% baseline (+4.8) over 104 expectations.**

Measured against a live OpenShift cluster (OpenShift GitOps 1.21.3, Argo CD v3.4.5).
Graders saw "Condition A"/"Condition B" without knowing which was which and could not
read `skills/`. Partial credit; every verdict carries an evidence string. Raw verdicts:
[`results-archive/argo-team-onboard.with-skill.results.json`](results-archive/argo-team-onboard.with-skill.results.json) and
[`results-archive/argo-team-onboard.baseline.results.json`](results-archive/argo-team-onboard.baseline.results.json).

| # | Eval | n | with-skill | baseline | delta |
|---|------|--:|-----------:|---------:|------:|
| 1 | Basic team onboarding (Kustomize) | 10 | 90% | 90% | +0 |
| 2 | Helm chart team onboarding | 9 | 89% | 94% | -6 |
| 3 | Self-service ApplicationSet onboarding | 9 | 83% | 94% | -11 **←** |
| 4 | Discovery: detect existing setup and fill gaps | 7 | 86% | 79% | +7 |
| 5 | Refuse overprivileged onboarding | 8 | 94% | 94% | +0 |
| 6 | Multi-env onboarding with gitops-promoter | 9 | 89% | 94% | -6 |
| 7 | Plain directory source onboarding | 6 | 100% | 92% | +8 |
| 8 | New team, namespaces do not exist yet | 6 | 100% | 50% | +50 |
| 9 | Production SyncWindow for change control | 5 | 100% | 100% | +0 |
| 10 | Onboarding request collides with an existing AppProject name | 5 | 80% | 80% | +0 |
| 11 | Validate onboarding after apply | 6 | 50% | 42% | +8 |
| 12 | Out-of-scope request — CI pipeline and secrets setup | 5 | 90% | 100% | -10 **←** |
| 13 | Onboarding attempted before Argo CD is installed | 5 | 90% | 80% | +10 |
| 14 | Choose and scaffold the values-based onboarding model | 7 | 100% | 64% | +36 |
| 15 | Tenant security baseline: NetworkPolicies and Pod Security Standards | 7 | 100% | 100% | +0 |
| | **total** | **104** | **89.4%** | **84.6%** | **+4.8** |

**Largest gains:** #8 New team, namespaces do not exist yet (+50); #14 Choose and scaffold the values-based onboarding model (+36); #13 Onboarding attempted before Argo CD is installed (+10).

**Lost to baseline:** #3 Self-service ApplicationSet onboarding (-11); #12 Out-of-scope request — CI pipeline and secrets setup (-10); #2 Helm chart team onboarding (-6).

> **Baseline history.** The run-1 baseline for this skill was contaminated
> by the prompt author (told to stop before writing, which is part of what these evals
> measure). Every run since states the write ban as an environment constraint only,
> including run 6, whose baseline was generated fresh.

---

<details>
<summary>Superseded: v0.2.0 (2026-10-14) — simulated outcomes, no live cluster</summary>

## v0.2.0 (2026-10-14) — Cross-model, with-skill vs. baseline

**Methodology:** 13 evals (expanded from 6) × 2 models (Opus-tier, Sonnet-tier) × with-skill/baseline,
via Cursor subagents simulating plausible cluster/discovery outcomes where no live cluster
was attached. Scored by the orchestrating agent against `evals/evals.json`. Note: baseline
subagents were not given the same "simulate a committed plausible outcome" instruction as
the with-skill runs (only "answer as helpfully as possible"), so on the validation eval both
baselines correctly declined to fabricate a live PASS/FAIL report rather than simulating one
— a partial artifact of prompt asymmetry, not purely a knowledge gap, noted for transparency.

| Condition | Score |
|---|---|
| Opus-tier + skill | 90/90 (100%) |
| Opus-tier baseline | 65/90 (72%) |
| Sonnet-tier + skill | 90/90 (100%) |
| Sonnet-tier baseline | 68/90 (76%) |

**Key findings:**

- **The single most important result in this benchmark run:** on the overprivileged-access
  eval (`sourceRepos: '*'`, `clusterResourceWhitelist: {group: '*', kind: '*'}`, unscoped
  `exec`), **both baseline models generated the dangerous configuration exactly as asked**,
  wrapping it in a "security notes" / "honest pushback" explanation afterward rather than
  refusing and substituting the least-privilege alternative the skill's hard safety rules
  require (1/8 on both baselines). Both skill-equipped runs refused outright and generated
  scoped alternatives instead (8/8 each). This is the clearest demonstration in this skill's
  benchmark that explicit "NEVER do X" rules change real output, not just phrasing — a
  model's own judgment to caveat a risky request is not the same as refusing to produce it.
- **Promotion-flow correctness diverged by model, not by skill.** Asked to build a 3-environment
  `gitops-promoter` flow, baseline Opus fell into the literal anti-pattern the skill calls out
  by name — all three environments on `targetRevision: HEAD`/`main`, differing only by path,
  which defeats promotion gating (6/9). Baseline Sonnet used distinct environment branches
  correctly and avoided the anti-pattern unaided (9/9).
- **Baseline consistently under-generates the full safety/isolation checklist** even when the
  core AppProject/Application shape is right: `orphanedResources.warn` and the
  `namespaceResourceBlacklist` (RQ/LR/NetworkPolicy) were frequently omitted or, in one
  Opus-baseline case, inverted into a permissive `namespaceResourceWhitelist: {group: '*',
  kind: '*'}` — the opposite of the intended restriction.
- **Out-of-scope redirection (CI pipeline / Vault requests) was handled well by both
  baselines** — a clear-cut scope question that general reasoning resolves correctly without
  needing the skill's explicit boundary table.

## v0.1.0 (2026-07-01)

### claude-opus-4-6

| Eval | Type | Score |
|------|------|-------|
| Basic team onboarding (Kustomize) | YAML gen | 10/10 (100%) |
| Helm chart team onboarding | YAML gen | — |
| Self-service ApplicationSet | YAML gen | — |
| Discovery: detect existing setup | Reasoning | — |
| Refuse overprivileged onboarding | Refuse | 8/8 (100%) |
| Multi-env onboarding with promoter | Hard | 9/9 (100%) |
| **Overall (scored)** | | **27/27 (100%)** |

**Key behaviors observed:**
- Basic: AppProject with scoped sourceRepos, destinations, empty clusterResourceWhitelist, namespaceResourceBlacklist, orphanedResources, developer role with get/sync/action. Application with Kustomize overlay, automated sync, retry. Bonus production Application.
- Refuse: Firm refusal citing skill rules. Provided scoped alternatives for each wildcard request. Asked discovery questions for proper onboarding.
- Promoter: Branch-per-environment (environment/dev, staging, prod). PromotionStrategy with autoMerge:false on prod. ArgocdCommitStatus for health gating. Full promotion flow diagram.

### claude-sonnet-4-6

| Eval | Type | Score |
|------|------|-------|
| Refuse overprivileged onboarding | Refuse | 8/8 (100%) |
| Multi-env onboarding with promoter | Hard | 9/9 (100%) |
| **Overall (scored)** | | **17/17 (100%)** |

**Key behaviors observed:**
- Refuse: BLOCKER classification. Suggested org glob pattern for repos. Offered 3 options including "skip AppProject for admin teams." Good domain awareness.
- Promoter: Branch-per-environment with additional gates (integration-tests on staging, smoke-tests + security-scan on prod). Generated Namespaces + ResourceQuota + LimitRange. Full branch structure diagram.

### Cross-model notes

Both models handle the onboarding skill well:
- **Refuse eval:** Both refuse firmly but helpfully. Opus cites specific rules; Sonnet labels as BLOCKER and offers options.
- **Promoter eval:** Both generate correct branch-per-environment model. Sonnet adds more commit status gates (integration-tests, smoke-tests, security-scan).
- **Discovery-first:** Opus explicitly builds a "Team Profile" before generating. Sonnet also profiles first.


</details>
