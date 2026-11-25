# Argo CD Application sync triage

Load through Workflow 2b in `../SKILL.md`. Reuse the installation and instance evidence
already gathered. File paths below are relative to this reference directory.

Sync status, not health status. An Application can be `Synced` and `Degraded` at the
same time — the live state matches git and the workload is still broken — and it can be
`OutOfSync` and `Healthy`, where everything is running and simply is not what git says.
A successful sync can address drift; it does not establish workload health.

For a workload-only failure with no sync blocker, use `app-health-triage.md`.
For mixed symptoms, investigate comparison and operation errors first, then follow
workload blockers into health triage and operator-owned permission failures into
`operator-rbac.md` (destination authorization) or
`operator-apps-in-any-namespace.md` (source watch/project/UI scope). Carry forward the evidence and outstanding checks;
a handoff continues this diagnosis and does not discard independent findings.

This workflow is read-only. Diagnose and report. Do not apply changes, and do not run
`argocd app sync`.

## How Argo CD computes sync status

For each managed resource, the controller compares the **desired** manifest against the
**live** object and normalizes before deciding:

1. Render the source — plain manifests, Helm, Kustomize, or a config management plugin.
   A render failure means there is no desired state, so the status becomes `Unknown`
   with a `ComparisonError` condition. Nothing is compared.
2. Associate live resources with the Application using the configured **resource
   tracking method**. Argo CD 3.x defaults to `annotation`, using
   `argocd.argoproj.io/tracking-id`; `label` uses `app.kubernetes.io/instance` and is
   a legacy or explicit opt-out setting. Check the running version and effective
   configuration before interpreting tags. A missing tag alone does not prove an
   object is absent: compare rendered and live resource identities too.
3. Normalize: drop fields Argo CD knows the API server defaults, then apply
   `spec.ignoreDifferences` on the Application and
   `resource.customizations.ignoreDifferences.<group>_<Kind>` from `argocd-cm`.
4. Anything left is a difference. One differing resource makes the whole Application
   `OutOfSync`.

The three sync statuses are `Synced`, `OutOfSync`, and `Unknown`. They describe the
**diff**, not whether a sync ran. A sync operation has its own separate phase.

### Diff state and operation state are different things

This is the distinction that drives the whole triage, and conflating the two is the most
common way a sync diagnosis goes wrong:

| Field | What it means |
|---|---|
| `.status.sync.status` | The result of the most recent comparison. A fact about the diff right now. |
| `.status.operationState.phase` | The outcome of the last sync **operation**: `Running`, `Terminating`, `Failed`, `Error`, or `Succeeded`. |

An Application can read `Synced` with `.status.operationState.phase: Failed` — the
failed sync was followed by a comparison that found no diff. It can also read
`OutOfSync` with phase `Succeeded`, when the desired revision changed, pruning was skipped, the operation was
selective, or live state subsequently changed. **Read both before routing.** A status alone does not tell you
whether a sync was attempted.

## Establish missing evidence

Reuse the current-run Application snapshot, ownership and CLI choice. If needed,
collect sync/health, operation phase/message/times, conditions, effective automation,
and desired versus operation revision(s) together. Workflow 2 in `debug-workflows.md`
has an example projection; it is not a prerequisite for a known symptom.

`Running`/`Terminating` and timestamps establish an ongoing operation; an absent
finishedAt alone is insufficient. Compare elapsed time with the actual hook/wave
progress before calling it stuck. For resource health needed in a handoff, use
`resource-health.md` unless a successful snapshot already supplies it.

## Route by state

Check in this order and load the first matching reference. Follow additional
references when its evidence identifies another blocker; do not restart a generic
workflow or repeat completed checks. A leaf's stop/return ends that branch only:
finish any outstanding health or operator investigation before the final report.

| Check | State | Reference |
|---|---|---|
| 1 | Sync status is `Unknown`, or there is a `ComparisonError` or `InvalidSpecError` condition | `sync-comparison-error.md` |
| 2 | `operationState.phase` is `Running` or `Terminating` and has been for a while | `sync-stuck.md` |
| 3 | `operationState.phase` is `Failed` or `Error` | `sync-failed.md` |
| 4 | Sync status is `OutOfSync` and no operation is running | `sync-outofsync.md` |
| 5 | Sync status is `Synced` but the cluster does not match what you expect | `sync-false-synced.md` |

Prioritize comparison errors before trusting drift counts or cached resource lists.
They do not invalidate independently observed live failures or operation evidence;
retain those findings and establish their freshness.

If the Application is `Synced`, the last operation `Succeeded`, and the cluster matches
the intended state, close the sync branch. Continue any outstanding health or operator
checks; matching Git does not prove a workload is healthy.

## Sustained OutOfSync

Use `sync-outofsync.md` for effective automation, windows, pruning and revision-aware
diff analysis. Absent `automated` or explicit `automated.enabled: false` disables
auto-sync; an empty object does not. Recent operation success alone proves neither
current convergence nor a competing writer. Compare operation and desired revisions
(including multi-source arrays), selected resources and prune results before inferring
a rewrite. A manual-sync policy is not itself a fault.

## Operator-managed instances change where the fix goes

On Red Hat OpenShift GitOps, the settings behind several sync causes are reconciled by
the operator. A direct edit to `argocd-cm` is reconciled back to the owning configuration, so
recommending one produces a fix that appears to work and then regresses.

| Setting | Lives in the `ArgoCD` CR as |
|---|---|
| `resource.customizations.ignoreDifferences.*` | `.spec.resourceIgnoreDifferences` |
| `application.resourceTrackingMethod` | `.spec.resourceTrackingMethod` |
| `resource.exclusions` / `resource.inclusions` | `.spec.resourceExclusions` / `.spec.resourceInclusions` |
| Other `argocd-cm` keys | Prefer a dedicated supported CR field; use `.spec.extraConfig` only where supported and not overridden by operator reconciliation |

Check whether the instance is operator-managed before writing any recommendation that
touches a ConfigMap:

```bash
$KCTL get cm argocd-cm -n "$NS" \
  -o jsonpath='{range .metadata.ownerReferences[*]}{.kind}/{.name}{"\n"}{end}'
```

An `ArgoCD/<name>` owner means report the CR field, never the ConfigMap key.

## Output

Follow the report route in `../SKILL.md`. State comparison status and operation phase
separately, with the relevant condition/result and revisions. Give one evidence-backed
causal chain per independent finding, confidence and unavailable checks. A failed
comparison limits drift conclusions, not independent health observations.

Manual-sync policy, a closed sync window or intentional pruning exclusions may require
no action. Do not invent a repair or execute a sync. For an operator setting, recommend
the supported owning CR/Git input; confirm its schema and impact before specifying it.
