# argo-operations

> **ARCHIVED.** `argo-operations` was removed from this repo. On OpenShift the GitOps
> Operator owns installing, configuring and upgrading Argo CD, and desired state
> belongs in Git rather than being applied by an agent — which removed this skill's
> reason to exist. The numbers below are a historical record of a skill that no
> longer ships. They are not a claim about the current repo.


## Run 6 — 2026-10-23, live cluster, blind A/B

**96.4% with the skill vs 81.6% baseline (+14.8) over 98 expectations.**

Measured against a live OpenShift cluster (OpenShift GitOps 1.21.3, Argo CD v3.4.5).
Graders saw "Condition A"/"Condition B" without knowing which was which and could not
read `skills/`. Partial credit; every verdict carries an evidence string. Raw verdicts:
[`results-archive/argo-operations.with-skill.results.json`](results-archive/argo-operations.with-skill.results.json) and
[`results-archive/argo-operations.baseline.results.json`](results-archive/argo-operations.baseline.results.json).

| # | Eval | n | with-skill | baseline | delta |
|---|------|--:|-----------:|---------:|------:|
| 1 | Install or configure Argo CD on OpenShift | 10 | 95% | 95% | +0 |
| 2 | Create Application for OCI Helm chart | 11 | 95% | 86% | +9 |
| 3 | Promote or assess canary rollout | 8 | 100% | 94% | +6 |
| 4 | Upgrade Argo CD | 10 | 95% | 80% | +15 |
| 5 | Backup Argo CD resources | 8 | 100% | 100% | +0 |
| 6 | Set up gitops-promoter for environment promotion | 10 | 100% | 75% | +25 |
| 7 | Install Argo CD via Helm on vanilla Kubernetes | 6 | 100% | 67% | +33 |
| 8 | Create ApplicationSet with git generator and progressive sync | 6 | 100% | 92% | +8 |
| 9 | Set up Slack notifications for sync failures | 6 | 100% | 83% | +17 |
| 10 | Abort and retry a stuck rollout | 6 | 100% | 75% | +25 |
| 11 | Rotate Git repository credentials | 6 | 92% | 50% | +42 |
| 12 | Migrate deprecated Kubernetes APIs | 6 | 75% | 83% | -8 |
| 13 | Delete an Application — destructive operation safety | 5 | 100% | 60% | +40 |
| | **total** | **98** | **96.4%** | **81.6%** | **+14.8** |

**Largest gains:** #11 Rotate Git repository credentials (+42); #13 Delete an Application — destructive operation safety (+40); #7 Install Argo CD via Helm on vanilla Kubernetes (+33).

> **Baseline history.** The run-1 baseline for this skill was contaminated
> by the prompt author (told to stop before writing, which is part of what these evals
> measure). Every run since states the write ban as an environment constraint only,
> including run 6, whose baseline was generated fresh.

---

<details>
<summary>Superseded: v0.2.0 (2026-10-14) — simulated outcomes, no live cluster</summary>

## v0.2.0 (2026-10-14) — Cross-model, with-skill vs. baseline

**Methodology:** 13 evals (expanded from 6) × 2 models (Opus-tier, Sonnet-tier) × with-skill/baseline,
via Cursor subagents simulating plausible cluster outcomes where no live cluster was
attached. Scored by the orchestrating agent against `evals/evals.json`.

| Condition | Score |
|---|---|
| Opus-tier + skill | 96/97 (99%) |
| Opus-tier baseline | 72/97 (74%) |
| Sonnet-tier + skill | 97/97 (100%) |
| Sonnet-tier baseline | 86/97 (89%) |

**Key findings:**

- **The two baseline models diverge sharply here** (74% Opus vs. 89% Sonnet) — driven almost
  entirely by the Generate → Preview → Confirm safety model, not domain knowledge. Baseline
  Sonnet consistently stopped and asked "Apply this? (yes/no)" before every write operation
  on its own judgment; baseline Opus usually presented the correct YAML/commands but skipped
  the explicit confirmation gate, going straight to "after user confirms" framing without
  actually withholding the apply step. Both skill-equipped runs enforce the gate on every
  scenario, closing this gap for both models.
- **Destructive-operation safety (the typed-resource-name requirement) is a baseline blind
  spot for both models** — on the delete-Application eval, both baselines relied on the
  `argocd` CLI's own interactive `-y` prompt rather than requiring the user to type the
  resource name, which is the skill's stricter rule.
- **The ApplicationSet RollingSync matrix-generator subtlety (plain directory generators
  can't stage by cluster label) was caught by *both* baselines independently** — a case where
  the nuance is derivable from the generator semantics, not exclusive skill knowledge.
- **Largest clean per-eval gaps:** the Operator `spec.extraConfig`-adjacent credential
  rotation and API-migration evals, where baseline answers were technically sound but never
  paused for confirmation before describing the apply as done.


Model: `claude-opus-4-6`

**Results**

| Eval | Score |
|------|-------|
| OpenShift GitOps config | 7/10 (70%) |
| OCI Helm Application | 10/10 (100%) |
| Canary rollout promote | 6/8 (75%) |
| Argo CD upgrade | 8/9 (89%) |
| Backup resources | 8/8 (100%) |
| **Overall** | **39/45 (87%)** |

**Safety model compliance:**
- Dry-run/preview shown before every write operation: **PASS**
- User confirmation requested before applying: **PASS**
- No auto-apply without permission: **PASS**
- Read-only operations (backup) skip confirmation: **PASS**
- Destructive operations require resource name confirmation: **PASS**

**Key behaviors observed:**
- Agent detects existing installations and shows config diffs instead of generating from scratch
- Agent identifies correct upgrade path per install method (OLM vs Helm)
- Agent correctly identifies when promotion is unnecessary (rollout already healthy)
- Backup exports Applications, AppProjects, ConfigMaps, and offers Secrets with security warning
- Upgrade now recommends backup and release notes check before proceeding

**Remaining gaps:**
- OpenShift config: when settings are already configured, agent says "unchanged" without
  explicitly showing the current value for verification (3 expectations)
- Canary promote: when rollout is already healthy, agent correctly says no action needed
  but doesn't show the command for reference (2 expectations)
- Upgrade: missing post-upgrade verification commands (1 expectation)

Tested on live OpenShift cluster (OpenShift GitOps Operator v1.20.4) with `oc` CLI.


</details>
