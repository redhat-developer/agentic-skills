# Argo CD Application health triage

Load through Workflow 2a in `../SKILL.md`. Reuse the installation and instance evidence
already gathered. File paths below are relative to this reference directory.

Health status, not sync status. An Application can be `Synced` and `Degraded` at the
same time: the comparison found no actionable drift under the configured diff rules, while a
health check reports failure. Diagnose that failure; `Synced` alone does not prove
every live field matches Git or establish that another sync is a remedy.

This workflow is read-only. Diagnose and report. Do not apply changes.

## How Argo CD computes health

Resolution order for a live resource in Argo CD 3.4:

1. If the object has a `deletionTimestamp` and no hook finalizer — `Progressing`,
   message `Pending deletion`. Nothing else is evaluated.
2. A custom Lua script from `resource.customizations.health.<group>_<Kind>` in
   `argocd-cm`, if one exists for the GVK. **A script that errors makes the resource
   `Unknown`, and the Lua error becomes the health message.**
3. The built-in check for the GVK — Deployment, StatefulSet, DaemonSet, ReplicaSet,
   Pod, Job, Service, Ingress, PVC, HPA and APIService; bundled Lua checks cover
   additional kinds. A child Application may require an explicit custom assessment.
4. No check for a non-terminating resource — no health status at all; it is skipped.
   An unassessed kind alone does not make the Application unhealthy.

Newer builds may assess before deletion and support custom `deletionMessage`;
errors can return `Unknown` instead of the default deletion status. Check installed
support only when the observed deletion assessment differs from the 3.4 rule.

### Rollup to the Application (Argo CD 3.4)

Application health starts at `Healthy` and becomes the **worst** health among the
resources that count. Worst is this order, best to worst:

`Healthy` → `Suspended` → `Progressing` → `Missing` → `Degraded` → `Unknown`

Two consequences that drive triage:

- **`Unknown` is the worst status, not a mild one.** A resource whose `Unknown` assessment
  counts in the rollup can mask lower-ranked failures in the aggregate.
- **Absent live resources do not individually lower Application health.** An app
  with a live degraded Deployment and an absent Service reports `Degraded`; keep
  the missing Service as a separate sync finding. When non-hook resources are
  expected but none are live, the aggregate becomes `Missing`.

### What is excluded from the rollup

These never affect Application health. Finding one of them broken does not explain the
status, and you must keep looking:

| Excluded | Rule |
|---|---|
| Resources annotated `argocd.argoproj.io/ignore-healthcheck: "true"` | Skipped outright. Note the exact spelling — `ignore-healthcheck`, one word. |
| Hooks, and resources in the `Skip` sync phase | Skipped. A failed `PreSync` hook Job does not show as Degraded here; it shows as a failed sync operation. |
| An Application that manages itself | Excluded so app-of-apps does not self-reference. |
| A resource with no live object | Its individual `Missing` health is skipped, regardless of kind. The all-resources-absent aggregate rule still applies. |
| A child `Application` that is `Missing` or `Unknown` | Excluded from the parent in an app-of-apps. |

Do not search for a special health-checkable missing kind. Check the whole expected
resource set and whether any live resources remain. A ConfigMap-only app with its
only resource absent can be `Missing`; a missing ConfigMap alongside a live Deployment
does not establish that aggregate state. A custom health check on a live resource may
also explicitly return `Missing`; inspect that override when the all-absent rule does
not explain the result. For older installations, verify the running version before
applying this rule. See the [3.4 rollup implementation](https://github.com/argoproj/argo-cd/blob/release-3.4/controller/health.go).

## Establish missing evidence

Reuse the Application and installation observations already captured. If status is
unknown, obtain health, sync, operation phase and conditions together; Workflow 2 in
`debug-workflows.md` provides a projection when needed. Do not repeat CLI/instance
discovery. Read `resource-health.md` before interpreting per-resource assessments
unless the successful current-run snapshot already supplies them.

## Route by status

Start with the reference matching the health status. Follow other references for
secondary findings or sync/operator causes exposed by the evidence. Reuse completed
checks; do not restart a generic workflow. A leaf's stop/return closes that branch,
not any outstanding investigation of other signals.

| Status | Reference | What it is |
|---|---|---|
| `Degraded` | `health-degraded.md` | A health check ran and reported failure |
| `Progressing` | `health-progressing.md` | Not healthy yet, still allowed to become healthy. Sustained is the symptom |
| `Missing` | `health-missing.md` | Expected resources have no live objects in the 3.4 aggregate, or a live custom check explicitly returns Missing |
| `Unknown` | `health-unknown.md` | Assessment returned `Unknown` or failed; inspect its message and Application conditions |

If the Application is `Healthy` or intentionally `Suspended`, do not invent an
aggregate-health fault. Independently reported resource failures still need checking. Continue any outstanding sync or operator investigation;
a healthy workload does not establish that those signals are clear.

When more than one resource is unhealthy, the Application status comes from the worst.
Diagnose that one, and list the others as additional findings rather than merging them
into one cause.

## Deployment deadlines

`Progressing` does not establish progress, including before a Deployment's deadline.
Read `health-progressing.md` and inspect the workload evidence.

## Output

Follow the report route in `../SKILL.md`. Include the aggregate health explanation and
one observed causal chain per independent fault. Preserve the identity/message of
resources contributing to the aggregate and distinguish masked or excluded faults.
Use High confidence for directly verified causes, Medium for supported but incomplete
chains, and Low for unresolved causes; name unavailable evidence.

No action is appropriate only when evidence establishes expected behavior: an
intentionally paused resource, a Job making progress, or a normal rollout. Being
inside a progress deadline alone does not establish that. Recommend authoritative
Git/ArgoCD CR fixes and apply the entry's effective automation rule when discussing
self-heal. Do not mutate resources during diagnosis.

Independent sync/operator findings follow their direct routes in `../SKILL.md`.
