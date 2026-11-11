# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed — the Argo skill set is reorganised around one principle

**Read the world, recommend the change, let Git carry it.** What remains either analyses
something, or acts on runtime state no controller owns. Six skills become four.

- **Removed `argo-team-onboard`** (104 expectations retire). Its whole output was desired
  state that belongs in a commit, and it sat below the portfolio average at +4.8.
- **Dissolved `argo-operations`.** On OpenShift the GitOps Operator owns installing,
  configuring and upgrading Argo CD — its eval for exactly that scored **+0 over 10
  expectations**, because the operator does the work. Authoring Applications and
  ApplicationSets belongs in Git. Credential rotation belongs in a secrets manager.
- **Preserved from it:** Rollout runtime control (promote/abort/retry) moved to
  `argo-cluster-debug`, since a Rollout paused awaiting promotion is runtime state Git
  cannot express. Destructive-delete safety moved into the shared protocol. Repository
  credential knowledge became documentation in `argo-knowledge`.
- **New `skills/gitops/write-safety.md`** — Generate → Preview → Blast radius → Confirm →
  Verify, plus the typed-resource-name rule, shared by the two write-capable skills.
  `argo-performance-tuning` previously referenced `argo-operations` by name for its write
  protocol; that dangling dependency was the one hard blocker in the change.
- **Narrowed `argo-knowledge` by 1,754 lines** (31%) on cross-model evidence — see below.
- **Added AppProject evals** (21 expectations). `app-projects.md` carried 308 lines no eval
  touched. **Fixed `argocd-app-health` → `argocd-health`** in three places; verified
  against `argoproj-labs/gitops-promoter` `constants.go`. Two evals had been grading *for*
  the broken value, so the suite rewarded a PromotionStrategy that would hang.

### Added — benchmark tooling, because the old process was lost

Runs 1-8 were produced by hand and nothing in the repo could reproduce them. When scope
changed, four skills had no way to be re-measured and their verdicts had to be withdrawn.

`scripts/run_eval_arm.py` and `scripts/grade_eval.py`, wired to `make baseline` /
`make with-skill` / `make grade`. Strong baseline with the same framing and tools as the
with-skill arm; isolation by construction (baseline runs from an empty directory); one
blind grader per comparison; a verbatim evidence quote behind every verdict; read-only
cluster access by allowlist rather than `--dangerously-skip-permissions`. The existing
`eval-*` targets remain, relabelled as what they are — a single-arm self-scored smoke
test, not a benchmark.

### Benchmarks — run 9, a clean break from runs 1-8

| skill                   |   n | with-skill | baseline |  delta |
|-------------------------|----:|-----------:|---------:|-------:|
| argo-performance-tuning | 107 |      94.9% |    57.9% | +36.9  |
| argo-repo-audit         |  85 |      96.5% |    68.8% | +27.6  |
| argo-cluster-debug      |  80 |      95.0% |    78.8% | +16.2  |
| argo-knowledge          | 153 |      95.4% |    86.9% |  +8.5  |
| **weighted overall**    | 425 |      95.4% |    74.5% | +20.9  |

Rank order is identical to runs 1-8, which is the evidence the harness measures the same
thing. Deltas run wider because the new grader is stricter and the with-skill arms sit
near ceiling, so only baselines have room to fall. **Do not compare run 9 to runs 1-8** —
the instrument changed.

### Added — first cross-model measurement

All nine prior runs used one model, so nothing tested whether a skill's value decays as
the base model improves — the premise the narrowing rests on. 16 evals x
{claude-opus-4-6, claude-opus-5} x {with-skill, baseline}:

    claude-opus-4-6   69.7% -> 94.3%   +24.6
    claude-opus-5     84.5% -> 96.2%   +11.7

The skill is worth more than twice as much on the older model. Baselines rose 69.7 -> 84.5
between generations while the with-skill ceiling barely moved. Four references tied or
lost on **both** models and were cut: `rollouts.md`, `openshift.md`, `notifications.md`,
`best-practices.md`. `agent-mode.md` was kept despite +0 on opus-5 — it is +40 on 4.6, and
this repo ships to agents that may run weaker models. Full method in
`benchmarks/cross-model-probe.md`.


### Benchmarks — run 2: re-measured all six skills, and measured the grader

Re-ran every suite against a live OpenShift cluster after fixing the defects run 1
surfaced, with the two contaminated baselines re-run clean.

|                          | with-skill | baseline |  delta | run 1 |
|--------------------------|-----------:|---------:|-------:|------:|
| argo-performance-tuning  |      94.2% |    66.8% | +27.4  | +21.6 |
| argo-repo-audit          |      97.5% |    81.2% | +16.2  |  +9.4 |
| argo-operations          |      93.8% |    84.4% |  +9.4  |  −3.6 |
| argo-knowledge           |      98.5% |    93.9% |  +4.5  |  +1.9 |
| argo-team-onboard        |      84.5% |    84.5% |   0.0  |  +4.4 |
| argo-cluster-debug       |      87.7% |    88.6% |  −0.9  |  +4.4 |
| **weighted**             |  **93.2%** | **83.4%**| **+9.8**| +6.3 |

**Two skills show no measurable benefit.** `argo-team-onboard` tied its baseline exactly
(87/103 each) and `argo-cluster-debug` came in fractionally behind. `team-onboard`'s
apparent +4.4 in run 1 was mostly a contaminated baseline, not a real gap.

**We measured grader variance instead of asserting it.** Four baselines were reused
unchanged and regraded by a fresh grader — same text, same expectations, so any
difference is the grader. Pooled agreement 92% over 369 expectations; drift −6.9 to +0.9.
Disagreements are nearly all one-directional (`pass` → `partial`), so the run-2 grader is
systematically stricter rather than noisy. Consequence: a stricter grader *widens* deltas
when the with-skill arm sits at ceiling — `argo-repo-audit` kept an identical 97.5% while
its regraded baseline fell 88.1% → 81.2%, moving the delta +9.4 → +16.2 with no change to
the skill. Within a run both arms share one grader, so direction and rank-ordering are the
trustworthy part; treat anything under ~5 points as indistinguishable from zero.

Run-1 verdicts preserved in `benchmarks/results-run1-2026-10-20/` so the drift table is
reproducible. Per-skill docs in `benchmarks/*.md` regenerated from the run-2 verdicts;
the older v0.2.0 simulated-outcome sections are retained but collapsed and marked
superseded.

### Fixed — argo-repo-audit: two scans that returned zero on their own fixtures

- The hardcoded-credential pipeline filtered comments with `grep -v "...\|#"`, which drops
  any line whose *value* contains `#`. It found **nothing** in
  `hardcoded-helm-password/app.yaml`, whose planted password deliberately contains a `#`
  — the fixture that exists to test exactly this. The filter is now anchored to `#` in
  value position. (The fixture value is synthetic test data, not a credential; release
  notes no longer reproduce it verbatim, to keep secret scanners from flagging prose.)
- The insecure-TLS scan matched only `insecure: true` and missed the quoted JSON form
  (`"insecure": true`) that appears in cluster Secrets.
- The duplicate-name check used a `kind:`/`name:` proximity grep with `-h`, printing no
  file paths despite the step requiring them, and breaking on any document not ordered
  kind-then-name. Replaced with a document-level `yq` scan keyed on kind|namespace|name.
- `ClusterAnalysisTemplate` appeared in three kind tables but shipped no schema, so
  kubeconform silently **skipped** those manifests rather than validating them.


### Fixed — argo-operations: the verification gap the benchmark exposed

`argo-operations` was the one skill that **lost** to its unaided baseline (90.1% vs
93.8%). All four of its outright failures were the same category, and the stored
per-expectation verdicts named it precisely:

| Eval | Expectation that failed | Baseline |
|------|------------------------|----------|
| 4 — upgrade | "Includes post-upgrade verification steps" | PASS |
| 7 — Helm install | "Verifies installation with `kubectl get pods` after apply" | PASS |
| 10 — abort/retry | "Reports the rollout's resulting phase after each step" | PARTIAL |
| 11 — credential rotation | "Includes a verification step after rotation" | PASS |

The safety model was **Generate → Preview → Confirm** — three steps, ending at the gate.
It never said "now check it worked". The baseline verified after acting, which is the
whole of the difference.

**Adds Step 4: Verify**, with a per-operation table (create/update, operator-managed
change, install, upgrade, sync, rollout promote/abort/retry, credential rotation,
delete) and four rules: report the output rather than claiming success, allow for
reconciliation lag, state failures plainly without auto-remediating, and summarise
read-only operations too. A fifth rule covers the case that actually caused three of the
four misses — **if the operation could not be executed, still state the verification
plan**. Dropping verification because nothing was applied is how this step disappears.

Procedure-level fixes, each targeting a specific failed expectation:

- **Abort/retry** now report the resulting phase with the expected end state named
  (`Degraded` + `abort: true` for abort; `Progressing` → `Healthy` for retry), plus the
  point the baseline made and the skill missed: **abort → retry is a loop, not a fix** —
  retry re-runs the same spec, so read the AnalysisRun failure first.
- **Upgrade** gains a four-part check, including that the CSV phase is authoritative and
  the Subscription's `state` is not — it reports `AtLatestKnown` while the CSV behind it
  is stuck, which is exactly what this cluster has been doing for 47 days.
- **Credential rotation** gains a connectivity test and a hard refresh. A credential that
  applies cleanly and cannot authenticate is the entire failure mode.
- **OpenShift operator install verification was broken**: it used
  `-l app.kubernetes.io/part-of=argocd`, which the operator does not set on pods —
  measured 0 of 9 on this cluster. A healthy install reported as "nothing deployed".
  Now enumerates pods and checks the ArgoCD CR phase.

Re-running the suite is the test of whether this closes the gap; it has not been re-run
yet, so the published −3.6 stands until it is.


### Added — real benchmark numbers, measured both ways

Ran all six suites twice against a live OpenShift cluster: once with the skills, once
with `skills/` off-limits. **572 expectations per condition, 1,144 verdicts**, each with
an evidence string, in `benchmarks/results/`.

| Skill | with-skill | baseline | delta |
|---|---:|---:|---:|
| argo-performance-tuning | 91.8% | 70.2% | +21.6 |
| argo-repo-audit | 97.5% | 88.1% | +9.4 |
| argo-cluster-debug | 92.1% | 87.7% | +4.4 |
| argo-team-onboard | 93.7% | 89.3% | +4.4 |
| argo-knowledge | 97.3% | 95.5% | +1.9 |
| argo-operations | 90.1% | 93.8% | **−3.6** |
| **Weighted** | **94.0%** | **87.7%** | **+6.3** |

The previously published numbers (claiming baselines of 47–93%) were measured against a
much weaker baseline and are replaced, not updated. The delta tracks how
product-specific each skill is: tuning, where answers depend on exact setting names and
operator-overridden defaults, gains most; general Argo CD knowledge gains least.

**`argo-operations` lost to its baseline** — four fails, all the same category: no
post-action verification. Generate → Preview → Confirm ends at the gate. Logged as a
design gap to fix rather than smoothed over.

Method: blind A/B (scorers never knew which condition they graded, seeded flips, mixed
outcomes), per-expectation grading with partial credit, identical prompts/tooling/cluster
and read-only limits in both conditions.

Four caveats are published with the numbers: two baselines were contaminated by the
prompt author (write-behaviour hints; excluded figures given), two mutually unsatisfiable
expectation pairs were live during scoring so the results are a floor, one input was
corrupted mid-run and caught before publication (would have read as +40 instead of +1.9
for argo-knowledge), and it is a single run on a single model.

### Fixed — two contradictory expectation pairs in the eval sets

No answer could satisfy both sides, so the suites capped their own ceiling and penalised
internal consistency:

- `argo-knowledge` eval 1 required omitting the `oci://` scheme from `repoURL`; eval 2
  required including it. Reconciled to the documented form.
- `argo-performance-tuning` evals 3 and 11 presented round-robin as a reasonable default
  while eval 21 required correcting the premise that it is production-hardened. All three
  now agree it is experimental.

### Fixed — `make score` silently dropped half its input

`score_evals.py` keyed results by skill name alone, so a skill's baseline and with-skill
files collided and one overwrote the other. Now keyed by (skill, condition), with a
warning on genuine duplicates. Also widens the column to fit condition-qualified names,
and the unblinder stitches sharded scorer output (needed when a suite is too large for
one grading pass) while rejecting duplicate eval ids.

### Changed — `KNOWN_DIVERGENCES` in the expectation validator

`spec.controller.sharding.algorithm` exists on OpenShift GitOps 1.21.3 but not in
upstream `argocd-operator` v0.18.0, which is where the shipped ArgoCD CR schema comes
from (Red Hat's build has no public raw URL). Rather than silence the mismatch, the
validator now prints known divergences with how each was verified, and still fails on
unknown paths. Worth knowing generally: **validating OpenShift GitOps content against
upstream `argocd-operator` produces both false positives and false negatives.**


### Fixed — three tuning defaults the OpenShift GitOps operator contradicts

All three verified against a live operator-managed cluster. They matter more now the
scope is OpenShift GitOps, because in each case the documented value is the *upstream*
one and the operator ships something different:

| Setting | Documented | Actual on OpenShift GitOps |
|---------|-----------|---------------------------|
| `ARGOCD_APPLICATION_CONTROLLER_KUBECTL_PARALLELISM_LIMIT` | default `20` | operator passes `--kubectl-parallelism-limit 10` — "match or sit below `operation.processors`" was reasoning from double the real baseline |
| `controller.resource.health.persist` | `false`, "leave it false" | `argocd-cmd-params-cm` has `"true"` and the controller runs `--persist-resource-health`. The advice inverts: you are already paying the churn, so `false` is an available *reduction* |
| `resource.exclusions` → Operator location | `spec.extraConfig` | the CR has a dedicated **`spec.resourceExclusions`** |

The `resource.exclusions` one was the most dangerous: it is a single YAML string that a
merge patch replaces wholesale, and the operator ships a populated default. Following the
old guidance would have deleted the shipped exclusions and *increased* watch load. The
reference now says read-append-write and shows the command.

Also documented why `spec.extraConfig` is the wrong home for it — not because it fails,
but because per the CRD *"ExtraConfig takes precedence over Argo CD CRD"*, so it silently
overrides the dedicated field and you debug the wrong layer.

### Fixed — 113 hardcoded `-n argocd` references

`argocd` is the upstream default namespace and is wrong on essentially every OpenShift
cluster, where the instance lives in `openshift-gitops` (and there are often several).
Every occurrence across 11 files is now `-n "$NS"`, with namespace resolution folded into
the existing platform/CLI detection block so it is established once:

```bash
$KCTL get argocd -A --no-headers 2>/dev/null || \
  $KCTL get pods -A -l app.kubernetes.io/part-of=argocd --no-headers | awk '{print $1}' | sort -u
NS=openshift-gitops
```

Reference files that are loaded standalone carry a short namespace preamble. The note also
covers the 62 `namespace: argocd` occurrences inside YAML manifests — an Application
created in `argocd` on a cluster whose instance is in `openshift-gitops` is simply never
picked up, with no error — while distinguishing that from an Application's *destination*
namespace, which is unrelated.

### Added — eval coverage for the last two uncovered references

Every reference in the repo now has at least one eval. Previously five had none; the last
two are closed here, plus `repo-patterns`:

- `argo-team-onboard/gitops-onboarding.md` — choosing and scaffolding the values-based
  model, and the tenant security baseline (PSS labels, default NetworkPolicies, and the
  DNS-egress exception that makes deny-all survivable).
- `argo-knowledge/best-practices.md` — resource tracking method collisions with other
  tools, and secret-management trade-offs.
- `argo-knowledge/repo-patterns.md` — choosing a repository pattern for a real fan-out.

Evals 81 → 86. `argo-knowledge` goes from ~25 KB/eval at the start of this work to ~11.

Also removed the leftover **Workflow Resource Management** section from
`argo-knowledge/references/best-practices.md`, missed in the scope cut.


### Added — reference content for the five operator-owned CRDs

`skills/argo-knowledge/references/openshift-gitops-operator.md` documents the CRDs with
no upstream Argo CD equivalent, which previously had zero or passing-mention coverage.
Every field was read from the installed CRD schemas, and **every manifest in the file was
validated with `oc apply --dry-run=server` against a live cluster** — 7 of 7 schema-valid.

| CRD | What it covers |
|-----|----------------|
| `RolloutManager` (`argoproj.io/v1alpha1`) | How Rollouts is deployed on OpenShift GitOps; `namespaceScoped`, `ha`, `nodePlacement`, `plugins`; editing the Deployment directly gets reverted |
| `NotificationsConfiguration` (`argoproj.io/v1alpha1`) | The operator-native path; all five fields are `map[string]string` (including `subscriptions`, which is easily mistaken for a list) |
| `NamespaceManagement` (`argoproj.io/v1beta1`) | The two-sided handshake with `ArgoCD.spec.namespaceManagement` — one side alone is inert and raises no event |
| `ImageUpdater` (`argocd-image-updater.argoproj.io/v1alpha1`) | The separate API group; `applicationRefs[]`, `manifestTargets.helm` vs `.kustomize`, `writeBackConfig` |
| `GitopsService` (`pipelines.openshift.io/v1alpha1`) | Why edits to the default instance's ArgoCD CR revert — confirmed `blockOwnerDeletion` ownerReference on the live cluster |

Closes with a "which CR owns which setting" table for the recurring question: *why will
this setting not stay changed?*

### Fixed — operations documented a notifications path the operator overwrites

`argo-operations/references/deployment.md` only described a hand-written
`argocd-notifications-cm`, which on OpenShift GitOps is reconciled away — notifications
work in testing and then silently stop. Flagged by the operations eval run. The section
now leads with the operator-native `ArgoCD.spec.notifications.enabled` +
`NotificationsConfiguration` path, gives a one-line check for which install type you are
on, and scopes the ConfigMap form to standalone Argo CD.

### Added — evals and schemas for the new surface

- Five `argo-knowledge` evals covering each CRD, written around the real failure modes
  (vanishing ConfigMap edits, one-sided NamespaceManagement, reverting CR patches,
  Helm/Kustomize `manifestTargets` mismatch). 8 → 13 evals; 76 → 81 total.
- Four more CRD schemas so `check-eval-expectations` validates the new content:
  `NotificationsConfiguration`, `NamespaceManagement` (argocd-operator),
  `RolloutManager` (argo-rollouts-manager), `ImageUpdater` (argocd-image-updater).
  8 → 12 schemas, and the validator is clean.


### Changed — scope narrowed to Red Hat OpenShift GitOps (BREAKING)

These skills target **OpenShift GitOps**, the productized Argo CD distribution, not the
whole Argo ecosystem. The boundary is what the operator actually owns, taken from the CSV
on a live cluster:

```
$ oc get csv -n openshift-gitops-operator -o json | jq -r \
    '.items[].spec.customresourcedefinitions.owned[]?.name' | sort -u
applications / applicationsets / appprojects / argocds
analysisruns / analysistemplates / clusteranalysistemplates / experiments / rollouts / rolloutmanagers
imageupdaters.argocd-image-updater / notificationsconfigurations / namespacemanagements / gitopsservices
```

**Removed — Argo Workflows and Argo Events** (~1,500 lines). They are separate upstream
projects; the operator owns none of their CRDs, and on OpenShift pipelines are normally
OpenShift Pipelines (Tekton). Removed: `references/workflows.md`, `references/events.md`,
2 of 11 canonical patterns, 2 of 7 debug workflows, the Workflow/Events CRD table rows and
troubleshooting sections, the Workflow audit checklist, 5 evals and 2 fixtures, 7 CRD
schemas, and the `argo` CLI from the Brewfile. README, manifests, agent definitions and
the banner now say OpenShift GitOps, with an explicit out-of-scope note pointing upstream
so the omission reads as deliberate.

**Kept — GitOps Promoter**, now labelled clearly as installed separately (argoproj-labs,
not operator-owned).

### Added — operator-owned CRDs that were missing entirely

Cutting out-of-scope content surfaced in-scope content that was never documented. All
verified against a live cluster:

| CRD | Previous coverage | Why it matters |
|-----|-------------------|----------------|
| `RolloutManager` (`argoproj.io/v1alpha1`) | **none** | How Argo Rollouts is actually deployed on OpenShift GitOps |
| `NotificationsConfiguration` (`argoproj.io/v1alpha1`) | **none** | Operator-managed notifications — a hand-written `argocd-notifications-cm` is reconciled away, which the operations eval hit |
| `NamespaceManagement` (`argoproj.io/v1beta1`) | passing mention | Which namespaces an instance may manage — directly relevant to onboarding |
| `ImageUpdater` (`argocd-image-updater.argoproj.io/v1alpha1`) | annotations only | It is an operator-owned CRD, in a **separate API group** |
| `GitopsService` (`pipelines.openshift.io/v1alpha1`) | **none** | Owns the default `openshift-gitops` instance; explains why manual edits to that CR revert |

Eval count 81 → 76; markdown 16,167 → 15,364 lines; CRD schemas now cover every in-scope
kind.


### Added (eval harness can now catch bad expectations)

- `scripts/check-eval-expectations.sh` — validates every `spec.*` path asserted in an eval
  expectation against the committed CRD schemas, wired into CI and `make
  test-expectations`. Nothing previously validated the expectations themselves, which is
  how three of them ended up grading **for** output the API server rejects or prunes.
  Running it immediately found two more:
  - eval 5 still asserted `spec.dex.openShiftOAuth` — the form unsupported since operator
    v0.8.0 — so it would have failed a correct `spec.sso.dex` answer.
  - eval 10 asserted CronWorkflow `spec.schedule`, removed in Workflows v3.6 in favour of
    the `spec.schedules` **list**. `references/workflows.md` had the same removed field,
    which produces a CronWorkflow that is created and then never fires.
- **Eight more CRD schemas** in `make download-schemas`: the ArgoCD CR (from
  `argocd-operator`, storage version `v1beta1`), Workflow, CronWorkflow, WorkflowTemplate,
  ClusterWorkflowTemplate, EventSource, Sensor, EventBus. 7 → 15. This closes the gap the
  repo-audit eval flagged (the CRD table listed 15 kinds while only 7 were validatable)
  and turns ~19 unverifiable expectation paths into real checks.

### Fixed (dev tooling that was quietly broken)

- **`make test-validate` failed** on the `applicationset` fixture: its overlays pulled in
  individual files from outside the kustomization root, which kustomize forbids. CI never
  caught it because the step ended in `|| true`. The fixture now uses a proper base
  (`apps/kustomization.yaml`) referenced as a directory, and all five fixtures build.
- **CI no longer swallows validation failures** for the clean fixtures. Intentionally
  broken ones under `targeted-bugs/` and `mixed-issues/` still tolerate findings.

### Fixed (argo-operations + promoter, from the live-cluster eval run)

- **`ArgoCDCommitStatus` was misspelled and its spec was wrong.** The live CRD's kind is
  `ArgoCDCommitStatus` (not `Argocd...`), and its `spec` takes **`promotionStrategyRef`**
  and **`applicationSelector`** — both required — plus optional `url`. The reference
  documented `gitRepositoryRef`, which is not a field on this kind, so the manifest failed
  admission twice over. Also corrected in eval 8's expectations.
- **`--dry-run=client` was the documented preview fallback but validates nothing.**
  Measured on-cluster: a manifest with a nonexistent field *and* a wrong-typed value is
  ACCEPTED by `--dry-run=client` and REJECTED by `--dry-run=server`. It also never merges
  with live state, so it cannot preview an update at all. The Preview table now defaults
  to `--dry-run=server` for creates and `kubectl diff` for updates, and the edge case
  says plainly that a client dry-run validated nothing.
- **Three credential-rotation recipes ended in `| kubectl apply -f -`**, skipping the
  skill's own Generate → Preview → Confirm model (Safety Rules 1 and 8) — on the one
  change most likely to lock Argo CD out of every repo at once. Split into
  generate/diff/confirm/apply, with a shred step. The repo-creds recipe was also missing
  `type=git`, without which Argo CD ignores the credential entirely.
- **The documented backup script reported success for empty backups.**
  `kubectl get ... -o yaml` exits 0 and writes `items: []` when nothing matches, so
  `cmd && echo "[OK]"` printed `[OK] Applications` while saving nothing — a false-positive
  backup. Now counts resources first. Also adds the **ArgoCD CR** to the backup, the most
  important object on an operator-managed cluster and previously omitted.
- **An invalid jsonpath in `progressive-delivery.md`** (a multi-line JSON-literal block)
  failed to parse on every cluster, not just this one. Replaced with a flat template, plus
  a check for the real ambiguity it was meant to resolve: a canary at
  `currentStepIndex == len(steps)` with `stableRS == currentPodHash` is **complete**, not
  stuck on the last step.

### Fixed (found by running the full eval suite against a live OpenShift cluster)

Six skills, 81 eval prompts, run against a real OpenShift cluster with three Argo CD
instances, Rollouts, Events and GitOps Promoter. Everything below was verified against
that cluster or its CRDs, not inferred.

**Severe — commands that silently report the wrong answer:**

- **`kubectl get applications` resolves to the wrong CRD.** Both
  `applications.app.k8s.io/v1beta1` and `applications.argoproj.io/v1alpha1` register the
  name `applications`. The unqualified form returns `No resources found` — with no error —
  while a real Argo CD Application exists. Proven on-cluster: bare form found nothing,
  `applications.argoproj.io` found `team-b-guestbook`. Healthy apps looked nonexistent and
  ApplicationSet output looked empty. Qualified across 9 files.
- **`-l app.kubernetes.io/part-of=argocd` matches nothing on Operator installs.** Measured
  0 of 9 pods on this cluster. Workflow 1 of `argo-cluster-debug` therefore concludes
  "Argo CD is not installed" on a cluster running three instances — and the edge-case
  table tells the user to stop there. Discovery now checks the `ArgoCD` CR first and falls
  back to the label for Helm installs.
- **`app.kubernetes.io/name=argocd-<component>` selectors never match on Operator
  installs** — the Operator labels workloads `<cr-name>-<component>`. Worst case was
  `argo-performance-tuning`'s OOM check, which silently reported no OOMs on a cluster
  actively OOMKilling `openshift-gitops-server` (10 restarts, exit 137). Both the replica
  and OOM checks now enumerate workloads and match on suffix; the replacement was run
  against the cluster and does surface the OOMKills.
- **`manualSync` was documented backwards in every occurrence.** The CRD says
  *"ManualSync enables manual syncs when they would otherwise be blocked"* — it is an
  escape hatch. The skills said `true` = "also block manual syncs" and `false` = "allow
  emergency syncs", which is the inverse. Anyone following it ships the opposite of their
  intended change-control policy and finds out during an incident. Fixed in
  `app-projects.md`, `onboarding-guide.md` (incl. its validation checklist) and
  `onboarding-variants.md`.

**`argo-performance-tuning` — new symptom coverage:**

- Added an `argocd-server` OOMKilled row. The table covered repo-server OOM but not
  server OOM, so a real, observed condition on this cluster routed nowhere.

**`argo-team-onboard` — defects in the GitOps-first rewrite itself:**

- `git status --short` + `git diff --stat` shows **nothing** for new tenant files, because
  they are untracked — which is every new-tenant onboarding, i.e. the main path. Now uses
  `git add -N` first.
- Safety Rules skipped number 5; Reference Index labelled self-service as Phase 3 when it
  is Phase 4.
- `onboarding-guide.md` listed NetworkPolicy as "Never (Out of Scope)" while SKILL.md
  Phase 2 made it *Always Generated* — same skill, both positions. The out-of-scope entry
  is retracted with an explanation.
- "Argo CD not installed" said *"Stop immediately"* in Edge Cases but *"you can still
  generate and commit"* in Prerequisites. Resolved in favour of not stopping, which is
  what the skill's own cluster-optional premise implies.
- The AppProject template shipped `sourceRepos: .../{{TEAM_NAME}}-*.git` directly under a
  comment saying "Never use '*'", while Rule 3 banned wildcards flatly. Both now draw the
  real line: a bounded org+team prefix glob is fine, anything that can match another
  team's repo is not.


### Fixed (content gaps found by the argo-knowledge eval run)

All verified against official Argo CD docs and a live OpenShift cluster running Argo CD,
Rollouts, and GitOps Promoter — not from memory.

- **`oci://` must not appear in a Helm `repoURL`.** Argo CD's docs state *"note: the
  `oci://` syntax is not included"*; the scheme is implied by `enableOCI: "true"` on the
  repository Secret. The repo had it wrong in `argo-operations/references/deployment.md`
  and in two `argo-team-onboard` references, and `argo-knowledge` documented OCI nowhere
  at all. Added the correct Application source form, the repository Secret registration
  (including that `enableOCI` must be the *string* `"true"`), and a Common Mistakes entry.
  Also corrected `argo-knowledge` eval 1, whose expectation asserted the `oci://` form.
- **Top-level `spec.dex` on the ArgoCD CR is dead.** Per the operator reference,
  *"`.spec.dex` is no longer supported in Argo CD operator v0.8.0 onwards, use
  `.spec.sso.dex` instead."* `argo-knowledge/references/openshift.md` and
  `argo-operations/references/setup.md` both generated the old form, so SSO would quietly
  never come up. Confirmed against the live cluster, whose ArgoCD CR uses
  `spec.sso.provider: dex` with `spec.dex` empty. (`day2-operations.md` already documented
  the migration correctly — the install reference just hadn't followed it.)
- **`ignoreApplicationDifferences` was absent from `argo-knowledge`.** Documented in
  `applicationsets.md` with its `name`/`jsonPointers`/`jqPathExpressions` fields, the
  image-updater case that needs it, and the distinction from the generated Application's
  own `ignoreDifferences`.
- **Multi-source Applications were undiscoverable.** The section existed but the
  SKILL.md index row never mentioned it and `patterns.md` had no multi-source pattern,
  despite Rule 5 directing the model to start from a numbered pattern. Added Pattern 11
  (chart + external values via `$values`) and fixed the index rows.
- **`oncePer` is scoped per trigger.** A single trigger driving pending → success/failure
  fires once per revision and leaves the commit status stuck on `pending`. Documented the
  one-trigger-per-state pattern, and that `operationState.syncResult.revision` is empty
  while the operation is `Running`.
- **Slack template fields were undocumented** (`username`, `icon`, `groupingKey`,
  `notifyBroadcast`, `deliveryPolicy`), and the example set both `attachments` and
  `blocks` with no note that they are two different rendering APIs.
- **GitOps Promoter CRD coverage was incomplete.** `ArgocdCommitStatus` appeared only in
  an example, and there was no `CommitStatus` field example or explanation of how a
  `PromotionStrategy` gate key is matched. Verified against the live cluster's 13
  promoter CRDs: gates reference `activeCommitStatuses[].key`, matched against
  `CommitStatus.spec.name`; an unmatched key blocks promotion silently rather than
  erroring. Also corrects the partial promoter list added to the CRD table in #1.
- **`agent-mode.md` now states its scope.** It is architecture prose with zero manifests;
  it now says so and routes installable questions upstream, rather than letting the model
  reconstruct pre-v1 setup steps from memory.

### Fixed (argo-repo-audit missed the escalation its own fixture tests for)

Surfaced by running the `argo-repo-audit` evals. The `tests/argo-repo-audit/targeted-bugs/subtle-rbac`
fixture exists to test detection of a privilege escalation with no wildcards in it — an
enumerated `clusterResourceWhitelist` granting `ClusterRole` + `ClusterRoleBinding`, plus
`applications, *` and `exec, create` on the project role. All three scanning commands
`security-audit.md` tells you to run returned **nothing** on it:

| Documented scan | Result on `subtle-rbac` |
|---|---|
| `clusterResourceWhitelist` wildcard | MISSED |
| RBAC triple-wildcard (`p,.*\*.*\*.*\*.*allow`) | MISSED |
| `sourceRepos` wildcard | MISSED |

The checklist prose covered the risk; every grep backing it only matched `'*'`. Added
enumerated-escalation and scoped-but-dangerous scans (ClusterRole/ClusterRoleBinding/
RoleBinding/CRD/webhook configs/SCC/APIService/StorageClass/PriorityClass, wildcard
actions, and any `exec` grant), with a table of why each kind is an escalation. Verified
the new scans catch the fixture and produce no false positives on `clean-repo`.

### Fixed (`validate.sh` refused to run instead of degrading)

`check_prereqs` hard-exited if **any** of yq/kustomize/kubeconform was missing, despite
SKILL.md promising to "skip gracefully". A machine with yq but no kubeconform therefore
got no YAML syntax check either, and a validation-only request had no automated path at
all. Each tool gates exactly one pass, so it now degrades per tool, labels each skipped
pass, and exits `2` only when all three are absent. The summary names what was skipped so
a reduced run is not mistaken for a clean full validation.

Also documented two coverage limits that could be read as false assurance: kubeconform
runs with `-skip=Secret` (so plain-text secrets can never be a Pass 2 finding), and only
Argo CD + Rollouts schemas ship locally (Workflows and Events kinds get no schema
coverage even with all tooling installed).

### Fixed (`preserveResourcesOnDeletion` was documented at the wrong path everywhere)

Surfaced by an eval run and confirmed against the repo's own committed CRD schema
(`skills/argo-repo-audit/assets/schemas/applicationset-argoproj-v1alpha1.json`): the field
exists **only** at `spec.syncPolicy.preserveResourcesOnDeletion`. There is no
`spec.preserveResourcesOnDeletion`. Because the ApplicationSet CRD is a structural schema,
the API server silently prunes the misplaced key — the manifest applies cleanly, review
looks correct, and the cluster has no deletion protection at all.

Every occurrence in the repo had it at spec level:

- `argo-knowledge/references/patterns.md` — patterns 3 and 4
- `argo-knowledge/references/applicationsets.md` — the spec overview block and the
  dedicated `## preserveResourcesOnDeletion` section (which contradicted the correct
  usage shown in the same file's Sync Policy section)
- `argo-operations/references/deployment.md` — ApplicationSet example
- `argo-repo-audit/references/best-practices.md` — the audit checklist, which meant the
  auditor **passed** repos with the broken key and would have flagged correct ones. Now
  reports the spec-level form as a finding.
- `argo-knowledge/evals/evals.json` — eval 2 explicitly instructed "Set
  preserveResourcesOnDeletion at the spec level" and asserted it in the expectations, so
  the benchmark was rewarding the broken output. Prompt and expectation corrected.

Note this slightly changes the argo-knowledge eval set, so the recorded 98% is not a
like-for-like comparison with future runs of eval 2.

### Fixed (argo-knowledge Rule 1 was factually wrong)

Rule 1 asserted "Every Argo CRD uses `apiVersion: argoproj.io/v1alpha1`", which the
skill's own references contradict: the OpenShift GitOps `ArgoCD` CR is
`argoproj.io/v1beta1`, and every GitOps Promoter kind is in a different API *group*
(`promoter.argoproj.io/v1alpha1`). A model following Rule 1 literally emits a rejected
manifest on those topics. Rule 1 now names the exceptions, and the CRD Table lists
`ArgoCD`, `PromotionStrategy`, `GitRepository`, `ScmProvider`, and `ArgocdCommitStatus`.

### Changed (argo-team-onboard is now GitOps-first) — BREAKING for existing users

Review feedback: *"I'm not a fan of argo-team-onboard if it's directly updating the Argo
CD config, this should be handled in git and managed by GitOps."* Correct, and it was a
design flaw — a GitOps onboarding skill whose write path was `kubectl apply` put the
tenant boundary outside Git: invisible in review, absent from the audit trail, and liable
to be reverted the next time anything reconciled.

- **The write is now a commit**, not an apply. The safety model changed from
  Generate → dry-run → apply to **Generate → `git diff` → confirm → commit/PR**, and the
  skill states that the tenant is not onboarded until Argo CD syncs.
- **`kubectl apply` is now the documented exception**, allowed only to bootstrap the first
  control loop, and the skill must label it as such and commit the same manifests.
- **Phase 1 Discovery now locates the GitOps repo first** and matches the existing tenant
  layout instead of inventing one. New Phase 3 covers the commit and handoff.
- **`git` is now the only hard requirement**; `kubectl`/`argocd` are optional and
  read-only. Onboarding works with no cluster access at all.
- New *Choosing the Onboarding Model* section: per-tenant values + chart (recommended),
  rendered manifests, or Kustomize overlay.

### Added (argo-team-onboard — security baseline and recommended model)

- `references/gitops-onboarding.md` — the recommended model, following Thomas Jungbauer's
  [project onboarding with GitOps and Helm](https://www.redhat.com/en/blog/project-onboarding-using-gitops-and-helm):
  per-tenant `values.yaml` rendered by a shared onboarding chart and discovered by an
  ApplicationSet with a `**/values.yaml` git generator. Includes t-shirt sizing with
  per-tenant override, and the two-Argo-CD-instance platform/tenant split.
- **Default NetworkPolicies are now generated for every tenant namespace.** The skill
  previously blacklisted `NetworkPolicy` via `namespaceResourceBlacklist` but never
  created any — so tenant namespaces shipped fully open to lateral traffic *and* teams
  were blocked from fixing it. Adds default-deny egress (with the DNS exception that
  makes it survivable), same-namespace, router ingress, and monitoring ingress.
- **Pod Security Standards labels on the Namespace template** —
  `pod-security.kubernetes.io/enforce: restricted` plus audit/warn and cluster monitoring.
  Previously absent entirely, so a tenant could run privileged pods regardless of how
  carefully the AppProject was scoped.

### Fixed (six-skill consistency)

- `assets/banner.svg` now shows a pill for all six skills; `performance-tuning` and
  `team-onboard` were missing.
- `make eval` ran only four of six skills — added `eval-operations` and
  `eval-team-onboard` (both skills already had `evals.json` and a benchmarks page).
- `.github/workflows/evals.yml` knew only three skills, and offered stale model IDs.
- `.codex-plugin/plugin.json` had placeholder `your-org` URLs and a three-capability
  description.
- `docs/USER_GUIDE.md` had no Team Onboarding section.
- README was missing the `gitops-promoter.md` reference row, and still explained a `—`
  placeholder that no longer appears in the benchmarks table.
- `make download-schemas` deleted the committed schemas first and had `|| true` on every
  download, so a network blip or an upstream CRD rename silently produced empty schema
  files — and `update-schemas.yml` would open a weekly PR deleting them. Downloads are now
  staged, verified non-empty and valid JSON, and only then swapped in.
- `argo-repo-audit` invoked its scripts at a CWD-relative path that does not resolve once
  the skill is installed as a plugin.
- `argo-knowledge` Pattern 10 combined Helm image-updater annotations with
  `write-back-target: kustomization` on a Kustomize source; each half is ignored by the
  other's source type.
- `argo-team-onboard` Phase 2/3 carried inline templates that contradicted `references/`:
  a different AppProject naming convention, snake_case vs camelCase `teams.yaml` fields,
  and a `teams:` array feeding a per-file generator's `{{ .team.name }}` (which cannot
  resolve, and hard-fails under `missingkey=error`).

### Added

- `scripts/check-skill-registration.sh`, wired into CI and `make test-registration`: a new
  skill cannot be added without being registered in the marketplace manifest, agent
  definition, Makefile eval targets, banner, README, and eval workflow. Verified it fails
  against the old four-pill banner.

### Changed (progressive disclosure)

Large always-loaded `SKILL.md` files now route to references, following the structure
`argo-performance-tuning` already used. No content was dropped — verified by comparing
every code block before and after.

- `argo-knowledge`: 822 → 189 lines; the 10 canonical YAML patterns moved to
  `references/patterns.md`, replaced by an index table.
- `argo-cluster-debug`: 695 → 176 lines; the 7 debugging workflows moved to
  `references/debug-workflows.md`, replaced by a symptom → workflow routing table.
- `argo-team-onboard`: 609 → 421 lines; Phase 2/3 inline manifests removed in favour of
  the existing `references/`, which are now the single source of truth for templates.

Evals should be re-run to confirm no regression, since answering now requires following a
reference pointer rather than reading everything up front.

### Added (argo-performance-tuning — web research delta)

- `references/tuning-settings.md` expanded with 11 settings/features verified against official
  Argo CD docs, upstream source, and benchmarked engineering blogs (the skill's reference was
  previously sourced from a single blog post). New coverage, roughly in order of impact:
  - `resource.ignoreResourceUpdatesEnabled` and the default `/status` ignore rule — the actual
    mechanism behind "high controller CPU with no real drift," which the skill previously only
    addressed indirectly via `timeout.reconciliation`.
  - `resource.exclusions` (ships with defaults since Argo CD 3.0) — stops watching known
    high-churn, non-GitOps kinds entirely.
  - `argocd.argoproj.io/manifest-generate-paths` annotation — the official fix for "one commit
    to a monorepo invalidates the cache for every Application in it," which the skill previously
    only worked around via shallow-clone depth / cache TTL advice. Documented with its known
    cache-coherency bugs (fixed as recently as mid-2026) as an explicit caveat.
  - `ARGOCD_K8S_CLIENT_QPS`/`BURST` (+ related TCP/TLS client family) — controller→managed-cluster
    API client tuning, with real AWS benchmark numbers (42min→11min sync time at 200/400).
  - Controller self-heal pacing (`controller.self.heal.timeout/backoff.*`).
  - `ARGOCD_APPLICATION_TREE_SHARD_SIZE` — Redis resource-tree sharding, distinct from cluster
    sharding.
  - Dynamic Cluster Distribution (alpha, v2.9+) — shard rebalancing without controller restarts,
    documented alongside two open 2025 upstream bugs on scale-down/scale-up
    (argoproj/argo-cd#24147, #24520).
  - Real consistent-hashing vs. round-robin benchmark data (CNOE blog) replacing the previous
    unsupported assertion that consistent-hashing "can improve balance"; also added the
    round-robin-is-still-experimental caveat the skill didn't carry before.
  - `controller.sync.timeout.seconds`, `controller.sync.wave.delay.seconds`,
    `controller.resource.health.persist` (new 3.0 default), and `controller.app.state.cache.expiration`
    (distinct from the repo-server's `ARGOCD_REPO_CACHE_EXPIRATION`, which the skill already covered).
- `SKILL.md` Phase 1 (Assess) gathers the new signals; Phase 2 (Diagnose) gained 6 new
  symptom→setting rows; Edge Cases gained 5 new entries for the above.
- 7 new eval scenarios (ids 15-21, bringing the total to 21) covering the high-impact new
  gaps — not yet benchmarked; see `benchmarks/argo-performance-tuning.md` for the existing
  14-eval / 99% vs. 47% result, which predates this expansion.
- All findings sourced and linked in a research canvas; one claim (exact Redis-compression /
  batch-event-processing setting names in 3.0) was left out of the skill because it could not be
  independently verified beyond the release changelog's entry titles.

### Added

- Expanded evals from 5/6/6 to 13 each for `argo-cluster-debug`, `argo-operations`, and
  `argo-team-onboard` — new scenarios target real gaps found by re-reading each skill's own
  `SKILL.md` (ApplicationSet debugging had zero prior coverage in `argo-cluster-debug`;
  `argo-operations` only ever tested the OpenShift Operator path, never Helm; `argo-team-onboard`
  never tested the plain-directory source type, the Phase 4 validation checklist, or the
  "Argo CD not installed" stop-and-redirect edge case).
- Real cross-model with-skill-vs-baseline benchmarks for all three expanded skills (Opus-tier
  + Sonnet-tier, same subagent methodology as `argo-performance-tuning`). See each skill's
  `benchmarks/*.md` for full per-eval breakdowns.

### Benchmark highlights

- `argo-team-onboard`: 100% with skill (both models) vs. 72–76% baseline. On the
  overprivileged-access eval, **both baseline models generated the requested wildcard
  `sourceRepos`/`clusterResourceWhitelist`/`exec` config as asked**, only adding a caveat
  afterward — neither refused. Both skill-equipped runs refused and substituted the scoped
  alternative per the skill's hard safety rules.
- `argo-operations`: 99–100% with skill vs. 74% (Opus baseline) / 89% (Sonnet baseline). The
  gap is driven almost entirely by the Generate → Preview → Confirm gate itself — baseline
  Sonnet adopted explicit confirmation prompts unprompted far more often than baseline Opus.
- `argo-cluster-debug`: 99–100% with skill vs. 93% baseline (both models) — the narrowest
  gap of any skill in this repo, since Argo troubleshooting patterns are common enough that
  baseline models already handle most of it; the skill's edge here is committing to one
  concrete root cause instead of a generic "check A, B, or C" list.

### Changed

- README Cross-Model comparison table expanded from `argo-knowledge` only to all 6 skills,
  with a new Sonnet Baseline column. Every cell is now a real, run score — no placeholder
  dashes remain anywhere in the table.

### Benchmark highlights (round 2)

- `argo-repo-audit`: first-ever baseline comparison for this skill (previously had none —
  it's a static local-file audit skill, not a live-cluster simulation). 98% (Opus+skill) /
  94% (Sonnet+skill) vs. 84% (both baselines, tied exactly) across all 13 real fixture-audit
  evals. The narrowest baseline gap of any skill in this repo besides `argo-cluster-debug`:
  GitOps security judgment ("wildcard RBAC is bad," "plaintext secrets are bad") is common
  DevSecOps knowledge both models already have. The skill's value here is comprehensiveness
  (ApplicationSet-specific checklist items like `goTemplateOptions`/`preserveResourcesOnDeletion`
  that baseline reliably skips) rather than teaching facts the models don't know. Also surfaced
  a real miss: Opus **with** the skill loaded failed to catch a duplicate-`AppProject`-name
  defect that both unaided baselines and Sonnet-with-skill all caught independently — and a
  severity-calibration miss on "HEAD in prod" (3 of 4 conditions, including skill-equipped
  Opus, over-escalated it to Critical when the skill's own rubric calls for Warning).
- `argo-knowledge`: added the one remaining untested condition (Sonnet unaided baseline),
  closing out the Cross-Model table completely. Sonnet's baseline scored 88% (77/88) —
  notably, it nailed the `argocd-agent` edge-fleet-architecture eval unaided (10/10), a sharp
  contrast with Opus's historical 30% baseline on the same eval. Weakest area unaided:
  `gitops-promoter` (58%) — branch-naming convention, `activeCommitStatuses` placement, and
  wrong parent-resource reference on `ArgocdCommitStatus` were all missed, consistent with the
  pattern that gitops-promoter (a newer, smaller project) is where unaided knowledge is least
  reliable across both models.

### Added

- **argo-performance-tuning** skill — diagnoses and tunes Argo CD / OpenShift GitOps
  performance and scalability. Maps symptoms (OOMKilled repo-server, sluggish UI/drift
  detection, Git rate-limiting, `context deadline exceeded`, high baseline polling load) to
  the specific repo-server, controller, or sharding setting that fixes them, for both
  standalone Argo CD and the OpenShift GitOps Operator `ArgoCD` CR. Reuses the
  generate/preview/confirm safety model from `argo-operations` for any live-cluster change.
  Distilled from [Tuning OpenShift GitOps for performance at scale](https://blog.stderr.at/gitopscollection/2026-03-27-openshift-gitops-performance-tuning/).
- `references/tuning-settings.md` — full settings reference (defaults, recommended values,
  standalone vs. Operator CR placement, common misconfigurations, tuning order of leverage)
- 14 eval scenarios for `argo-performance-tuning`, covering core symptom diagnosis plus
  edge cases (single-cluster sharding refusal, Operator misconfiguration correction,
  floating-tag cache pushback, unsupported sharding algorithm, multi-symptom prioritization,
  safety-model compliance, standalone vs. Operator placement)
- Routing entries for the new skill in the `argocd` agent, `argo-operations` redirect table,
  README, and USER_GUIDE

### Benchmarks

- argo-performance-tuning: 99% (Opus-tier) / 100% (Sonnet-tier) with skill vs. 47% / 56%
  unaided baseline — +52% / +44% delta across all 14 evals on both models. Largest deltas on
  the Operator `spec.extraConfig` processors misconfiguration (baseline Opus validated the
  broken request outright, 0/5), the three-way timeout alignment (0/5 baseline Opus), and the
  Git `ls-remote` rate-limit setting (unknown to both unaided baselines). See
  `benchmarks/argo-performance-tuning.md`.

## [0.1.0] - 2026-06-04

### Added

- **argo-knowledge** skill — answers questions about the full Argo ecosystem and generates
  validated YAML for all Argo CRDs (Application, ApplicationSet, AppProject, Rollout,
  AnalysisTemplate, Workflow, EventSource, Sensor, and more)
- **argo-repo-audit** skill — audits GitOps repositories for security issues, best practice
  violations, and operational gaps with structured prioritized reports
- **argo-cluster-debug** skill — debugs Argo resources on live Kubernetes/OpenShift clusters
  with systematic workflows for Applications, Rollouts, Workflows, and Events
- **argo-operations** skill — installs, deploys, promotes, and maintains Argo resources with
  a 3-step safety model (generate → preview → confirm)
- 15 reference docs covering Applications, ApplicationSets, AppProjects, Rollouts, Workflows,
  Events, notifications, image updater, repo patterns, best practices, argocd-agent, multi-tenancy,
  OpenShift GitOps, gitops-promoter
- 7 bundled Argo CRD schemas for offline kubeconform validation
- 3 test fixtures (app-of-apps, applicationset, mixed-issues) with 37 YAML files
- 19 eval scenarios across all 4 skills with benchmarks
- Agent configs for Claude Code, GitHub Copilot, and Codex
- CI workflows for validation, releases, evals, and weekly schema updates
- Pre-commit hook for PII/secret scanning
- SVG banner and terminal-style preview screenshots in README

### Benchmarks

- argo-knowledge: 97% with skill vs 86% baseline (+11%), +70% on argocd-agent
- argo-repo-audit: 100% — catches all Critical security issues
- argo-cluster-debug: 97.5% on advanced live cluster evals
- argo-operations: 87% — safety model fully compliant
