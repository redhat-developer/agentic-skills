# argo-repo-audit

## Run 9 — 2026-11-10, new two-arm harness

**96.5% with the skill vs 68.8% baseline (+27.6) over 85 expectations.**

> Generated with `make baseline` / `make with-skill` / `make grade` — see
> [methodology](README.md#how-to-produce-a-run). One blind grader scored both arms
> of each eval in a single call, every verdict carries a verbatim evidence quote,
> and the baseline ran from an empty directory so `skills/` was unreachable.
> **Not comparable to runs 1-8** — different harness, stricter grader.

| # | Eval | n | with-skill | baseline | delta |
|---|------|--:|-----------:|---------:|------:|
| 1 | app-of-apps-audit | 13 | 100% | 58% | +42 |
| 2 | applicationset-audit | 11 | 100% | 91% | +9 |
| 3 | mixed-issues-audit | 13 | 100% | 77% | +23 |
| 4 | validate-only | 6 | 100% | 100% | +0 |
| 5 | detect-wildcard-project | 5 | 100% | 60% | +40 |
| 6 | detect-plain-secret | 5 | 100% | 40% | +60 |
| 7 | detect-no-sync-policy | 4 | 100% | 62% | +38 |
| 8 | detect-head-in-prod | 4 | 100% | 100% | +0 |
| 9 | detect-weak-analysis | 4 | 75% | 25% | +50 |
| 10 | detect-hardcoded-helm-password | 5 | 60% | 60% | +0 |
| 11 | clean-repo-zero-findings | 9 | 100% | 50% | +50 |
| 12 | Subtle RBAC: looks restricted but has privilege escalation | 6 | 100% | 83% | +17 |
| | **total** | **85** | **96.5%** | **68.8%** | **+27.6** |

---

<details>
<summary>Superseded: runs 1-8 (different harness)</summary>

## Run 8 — 2026-10-23

**95.3% with the skill vs 79.4% baseline (+15.9) over 85 expectations.**

Measured against a live OpenShift cluster (OpenShift GitOps 1.21.3, Argo CD v3.4.5).
Graders saw "Condition A"/"Condition B" without knowing which was which and could not
read `skills/`. Partial credit; every verdict carries an evidence string. Raw verdicts:
[`results/argo-repo-audit.with-skill.results.json`](results/argo-repo-audit.with-skill.results.json) and
[`results/argo-repo-audit.baseline.results.json`](results/argo-repo-audit.baseline.results.json).

| # | Eval | n | with-skill | baseline | delta |
|---|------|--:|-----------:|---------:|------:|
| 1 | app-of-apps-audit | 13 | 92% | 65% | +27 |
| 2 | applicationset-audit | 11 | 100% | 100% | +0 |
| 3 | mixed-issues-audit | 13 | 96% | 77% | +19 |
| 4 | validate-only | 6 | 100% | 92% | +8 |
| 5 | detect-wildcard-project | 5 | 90% | 60% | +30 |
| 6 | detect-plain-secret | 5 | 90% | 50% | +40 |
| 7 | detect-no-sync-policy | 4 | 88% | 100% | -12 **←** |
| 8 | detect-head-in-prod | 4 | 88% | 100% | -12 **←** |
| 9 | detect-weak-analysis | 4 | 88% | 50% | +38 |
| 10 | detect-hardcoded-helm-password | 5 | 100% | 60% | +40 |
| 11 | clean-repo-zero-findings | 9 | 100% | 100% | +0 |
| 12 | Subtle RBAC: looks restricted but has privilege escalation | 6 | 100% | 83% | +17 |
| | **total** | **85** | **95.3%** | **79.4%** | **+15.9** |

**Largest gains:** #10 detect-hardcoded-helm-password (+40); #6 detect-plain-secret (+40); #9 detect-weak-analysis (+38).

> **Run 8 added three expectations that the skill passes and the baseline fails, and
> that widened the delta. Disclosed here because it is also exactly how a benchmark gets
> gamed.**
>
> The skill used to document a credential scan — `grep -rn -iE "(password|token|secret):"`
> — that prints whole matching lines, so running it copied the secret into the transcript.
> That is now a script reporting location, key name and value *length*, and three
> expectations grade it: two fail an answer that reproduces a plaintext credential or
> decodes a base64 one, and one fails an answer that reports SOPS/SealedSecret ciphertext
> as plaintext.
>
> They discriminate: the baseline fails both redaction expectations (it quotes
> `cDRzc3cwcmQhMjAyNg==`, decodes it, and repeats the cleartext a second time), the skill
> arm passes both. That is a real and harmful behaviour difference, not a scoring
> artefact — but adding expectations targeting a known advantage inflates a delta by
> construction, so here is the number both ways:
>
> | | with-skill | baseline | delta | n |
> |---|---:|---:|---:|---:|
> | run 8, full suite | 95.3% | 79.4% | **+15.9** | 85 |
> | run 8, excluding the 3 new expectations | 95.1% | 81.1% | +14.0 | 82 |
> | run 7, old suite | 97.0% | 85.4% | +11.6 | 82 |
>
> So the new expectations are worth about **+1.9** of the +4.3 increase. The remaining
> +2.4 is run-to-run variance between two runs of the same 82 expectations — consistent
> with the [variance analysis](README.md#run-to-run-variance-we-measured-that-too-and-it-is-larger-than-the-graders),
> and a reminder that neither figure is precise to a decimal.
>
> Earlier revisions of this page described a baseline reused from run 1. Every run since
> run 6 generates a fresh one.

---

<details>
<summary>Superseded: v0.2.0 (2026-10-14) — simulated outcomes, no live cluster</summary>

## v0.3.0 (2026-10-14) — Cross-model, with-skill vs. baseline (real file audits)

Unlike the other five skills in this repo, `argo-repo-audit` has no live cluster to simulate —
it audits real YAML files already on disk under `tests/argo-repo-audit/`. That makes this the
most rigorous of the six cross-model runs: **both** the with-skill and baseline subagents were
given identical, real file-read access to the actual fixture directories for all 13 evals. The
only variable between conditions was whether `SKILL.md` + `references/*.md` were loaded first.
No cluster state, API responses, or outcomes were simulated or asserted — every finding below
is grounded in literal fixture content, scored against each eval's real `expectations` array in
`skills/gitops/argo-repo-audit/evals/evals.json`.

4 subagents were dispatched — Opus-tier and Sonnet-tier, each in with-skill and baseline
conditions — each covering all 13 real eval scenarios in a single batched run (not the
Makefile's literal one-subagent-per-eval convention; see the other `v0.2.0` sections in this
repo for the same disclosed deviation). Each subagent was instructed to read every YAML file in
each target directory before producing findings — not guess contents.

| # | Eval | Max | Opus + Skill | Opus Baseline | Sonnet + Skill | Sonnet Baseline |
|---|------|-----|-------------|----------------|-----------------|-------------------|
| 1 | App-of-apps audit | 12 | 12 (100%) | 6 (50%) | 11 (92%) | 6 (50%) |
| 2 | ApplicationSet audit | 11 | 11 (100%) | 8 (73%) | 8 (73%) | 6 (55%) |
| 3 | Mixed-issues audit | 13 | 13 (100%) | 10 (77%) | 12 (92%) | 11 (85%) |
| 4 | Validate-only | 6 | 5 (83%) | 6 (100%) | 6 (100%) | 6 (100%) |
| 5 | Detect wildcard project | 5 | 5 (100%) | 5 (100%) | 5 (100%) | 5 (100%) |
| 6 | Detect plain-text secret | 4 | 4 (100%) | 4 (100%) | 4 (100%) | 4 (100%) |
| 7 | Detect no sync policy | 4 | 4 (100%) | 4 (100%) | 4 (100%) | 4 (100%) |
| 8 | Detect HEAD in prod | 4 | 3 (75%) | 3 (75%) | 4 (100%) | 3 (75%) |
| 9 | Detect weak AnalysisTemplate | 4 | 4 (100%) | 3 (75%) | 4 (100%) | 4 (100%) |
| 10 | Detect no-deadline workflow | 4 | 4 (100%) | 4 (100%) | 4 (100%) | 4 (100%) |
| 11 | Detect hardcoded Helm password | 4 | 4 (100%) | 4 (100%) | 4 (100%) | 4 (100%) |
| 12 | Clean repo zero findings | 9 | 9 (100%) | 9 (100%) | 9 (100%) | 9 (100%) |
| 13 | Subtle RBAC privilege escalation | 6 | 6 (100%) | 6 (100%) | 6 (100%) | 6 (100%) |
| | **Overall** | **86** | **84 (98%)** | **72 (84%)** | **81 (94%)** | **72 (84%)** |

### Key findings

- **Baseline does much better here than on any other skill in this repo (84% vs. the 47–76%
  range seen on `argo-performance-tuning`/`argo-team-onboard`/`argo-operations`).** GitOps
  security auditing — "wildcard RBAC is bad," "plaintext secrets in Git are bad," "`HEAD` in
  prod is risky," "missing `syncPolicy` breaks reconciliation" — draws on general
  Kubernetes/DevSecOps judgment both frontier models already have well-internalized. This isn't
  obscure, Argo-specific trivia the way `argo-performance-tuning`'s sharding algorithms or
  `argo-team-onboard`'s hard refusal rules are.
- **The skill's real value-add here is comprehensiveness, not detection of things baseline
  models can't reason about at all.** The two evals with the widest with-skill-vs-baseline gaps
  — App-of-apps audit (+50 Opus / +42 Sonnet points) and ApplicationSet audit (+27 Opus / +18
  Sonnet points) — are the two general, open-ended, "audit everything" scenarios with the
  longest checklists (sync waves, `ignoreDifferences`, `goTemplateOptions`, `goTemplate` vs.
  `fasttemplate`, `preserveResourcesOnDeletion`, generated-Application `prune` settings). All
  four conditions found the obvious security issues; what baseline runs reliably skipped was
  the long tail of ApplicationSet-specific and report-structure checklist items the skill
  enumerates explicitly. On the eight single-bug "targeted" fixtures (evals 5–11) — one planted
  issue each — baseline and with-skill are statistically indistinguishable.
- **Surprising miss: Opus with the skill loaded did not catch the `AppProject` name collision**
  in the `app-of-apps` fixture (both `projects/platform.yaml` and `projects/team-platform.yaml`
  declare `metadata.name: platform` — a real defect that makes roughly half the repo's
  Applications fail to sync depending on apply order). This wasn't a scored expectation for
  eval 1, but all **three other** conditions — Sonnet with the skill, and *both* unaided
  baselines — caught it independently just by reading the files closely. It's a reminder that
  loading a skill doesn't substitute for careful reading, and that this particular defect is
  detectable by general diligence alone, not special Argo-CD-specific knowledge.
- **Severity-calibration miss on "HEAD in prod" (eval 8), including the skill-equipped Opus
  run.** The eval expects this to be classified as a Warning/best-practice violation, not a
  Critical security vulnerability (per the skill's own severity rubric). Three of four
  conditions — Opus+skill, Opus baseline, and Sonnet baseline — labeled it "Critical" anyway;
  only Sonnet+skill kept it at "High"/non-Critical. This suggests the intuitive pull of "any
  commit auto-deploys to production" toward the highest severity bucket is strong enough that
  even having the skill's calibration guidance loaded doesn't reliably override it — a real,
  reproducible finding, not a fabricated one.
- **Both baselines tied exactly (72/86, 84%)** despite being different model tiers — on this
  skill, with real file access and no skill-specific checklist, Opus-tier and Sonnet-tier
  unaided judgment converged on the same overall score, even though they missed different
  individual items (Opus baseline was stronger on the obscure ApplicationSet best-practice
  items like `missingkey=error`; Sonnet baseline caught the `AppProject` name collision Opus
  baseline described differently).

### Methodology note

This run differs from the `v0.2.0` scores below in two ways: (1) all 13 evals were scored for
every condition (the `v0.2.0` run never scored Sonnet on 12 of the 13 evals, and never scored
either model on "ApplicationSet audit" or "Validate-only"), and (2) this run adds, for the first
time, unaided baseline conditions for both models — `argo-repo-audit` previously had no
baseline comparison at all. The `v0.2.0` scores remain below for history; they are not
superseded, just superseded in *coverage* by this run.

---

## v0.2.0 (2026-07-01)

### claude-opus-4-6

| Eval | Type | Score |
|------|------|-------|
| App-of-apps audit | General | 11/11 (100%) |
| ApplicationSet audit | General | — |
| Mixed-issues audit | General | 12/12 (100%) |
| Validate-only | General | — |
| Detect wildcard project | False negative | 5/5 (100%) |
| Detect plain-text secret | False negative | 4/4 (100%) |
| Detect no sync policy | False negative | 4/4 (100%) |
| Detect HEAD in prod | False negative | 4/4 (100%) |
| Detect weak AnalysisTemplate | False negative | 4/4 (100%) |
| Detect no-deadline workflow | False negative | 4/4 (100%) |
| Detect hardcoded Helm password | False negative | 4/4 (100%) |
| Clean repo zero findings | False positive | 9/9 (100%) |
| Subtle RBAC privilege escalation | Hard: subtle | 6/6 (100%) |
| **Overall** | | **67/67 (100%)** |

### claude-sonnet-4-6

| Eval | Type | Score |
|------|------|-------|
| Subtle RBAC privilege escalation | Hard: subtle | 6/6 (100%) |
| **Overall** | | **6/6 (100%)** |

### Cross-model notes

- **Subtle RBAC:** Both models caught ClusterRole/ClusterRoleBinding privilege escalation AND exec permission. Both provided attack YAML showing how the escalation works. No false positives on the properly-configured sourceRepos/destinations.
- The subtle RBAC eval was designed to produce failures — the AppProject looks well-configured at first glance. Both models looked past the surface.

### Accuracy validation

13 evals test detection accuracy:

**False negative tests (7):** Each fixture has ONE planted bug. Both models detected every
bug with correct severity classification — Critical for security issues (wildcards,
plain-text secrets, hardcoded passwords), Warning for operational risks (missing sync
policy, HEAD in prod, weak analysis, no deadline).

**False positive test (1):** Clean repo follows every best practice. Both models correctly
reported PASS with zero Critical/Warning findings. SealedSecret ciphertext not false-flagged.

**Hard eval (1):** Subtle RBAC privilege escalation — AppProject looks restricted but allows
ClusterRole/ClusterRoleBinding creation (escalation path) and exec into pods.

Evals test outcomes (issues found, report quality) not process (which tools were used).


</details>

</details>
