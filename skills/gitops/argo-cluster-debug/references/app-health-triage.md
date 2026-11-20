# Argo CD Application health triage

Load through Workflow 2a in `../SKILL.md`. Reuse the installation and instance evidence
already gathered. File paths below are relative to this reference directory.

Health status, not sync status. An Application can be `Synced` and `Degraded` at the
same time: the live state matches git and the workload is still broken. When that is
what you see, drift is not the cause and reconciling again will not help.

This workflow is read-only. Diagnose and report. Do not apply changes.

## Unattended diagnosis

When this workflow is used by an automated diagnosis run with no human in the
loop, do not ask questions. Gather the evidence you can
reach, name the most probable cause, and state your confidence and what you could not
check. An honest `Low` confidence diagnosis is useful. A question is not.

## How Argo CD computes health

Resolution order for a live resource:

1. If the object has a `deletionTimestamp` and no hook finalizer — `Progressing`,
   message `Pending deletion`. Nothing else is evaluated.
2. A custom Lua script from `resource.customizations.health.<group>_<Kind>` in
   `argocd-cm`, if one exists for the GVK. **A script that errors makes the resource
   `Unknown`, and the Lua error becomes the health message.**
3. The built-in check for the GVK — Deployment, StatefulSet, DaemonSet, ReplicaSet,
   Pod, Job, Service, Ingress, PVC, HPA, APIService, and Argo CD's own kinds.
4. No check for the GVK — no health status at all. The resource is skipped. A CRD that
   Argo CD does not know how to assess never makes an Application unhealthy.

### Rollup to the Application (Argo CD 3.4)

Application health starts at `Healthy` and becomes the **worst** health among the
resources that count. Worst is this order, best to worst:

`Healthy` → `Suspended` → `Progressing` → `Missing` → `Degraded` → `Unknown`

Two consequences that drive triage:

- **`Unknown` is the worst status, not a mild one.** One resource with a broken health
  check makes the whole Application `Unknown` and hides every other problem in it.
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

## Before any check

Resolve the CLI. On OpenShift, `oc` is the default.

```bash
if command -v oc >/dev/null 2>&1 && oc api-resources --api-group=route.openshift.io 2>/dev/null | grep -q routes; then
  KCTL=oc
elif command -v kubectl >/dev/null 2>&1; then
  KCTL=kubectl
elif command -v oc >/dev/null 2>&1; then
  KCTL=oc
else
  echo "ERROR: no cluster CLI found — install kubectl or oc" >&2; exit 1
fi
```

Always `applications.argoproj.io`, never the short name `application`: on Open Cluster
Management clusters the short name resolves to `applications.app.k8s.io` and a miss
looks like the Application does not exist.

Establish the status and the responsible resource before routing:

```bash
APP=<application-name>
APP_NS=<namespace-of-the-application-object>

# The Argo CD instance that owns this Application. Needed for controller logs,
# argocd-cm, and cluster secrets. List the instances and pick the owning one.
$KCTL get argocd -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
NS=<namespace-of-the-ArgoCD-CR>
CR=<name-of-the-ArgoCD-CR>

$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='health={.status.health.status}{"\n"}message={.status.health.message}{"\n"}sync={.status.sync.status}{"\n"}'
```

Load `resource-health.md` to obtain the resource assessments before selecting a leaf.
Argo CD 3.x normally stores those outside the Application CR. Empty inline health
fields alone establish neither a resource fault nor the absence of one.

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
| `Unknown` | `health-unknown.md` | Health could not be computed. Usually a broken check, not a broken workload |

If the Application is `Healthy` or intentionally `Suspended`, close the health branch
without inventing a fault. Continue any outstanding sync or operator investigation;
a healthy workload does not establish that those signals are clear.

When more than one resource is unhealthy, the Application status comes from the worst.
Diagnose that one, and list the others as additional findings rather than merging them
into one cause.

## Grace periods lie about Deployments

An automated trigger that fires after a few minutes of sustained unhealthy status will
catch a failing Deployment while it is still `Progressing`, not `Degraded`. A
Deployment only becomes `Degraded` when its `Progressing` condition reaches
`ProgressDeadlineExceeded`, and `progressDeadlineSeconds` defaults to 600 — ten
minutes. So for the first ten minutes, a Deployment whose pods cannot start and a
Deployment that is rolling out normally report the same health status.

Never read `Progressing` as "it is still working." Go to `health-progressing.md`
and check the pods.

## Output

Report these, in this order. A cause with no supporting output is not a diagnosis.

1. **Status and source.** The Application health status, and the specific resource and
   health message that produced it. Quote the message.
2. **Root cause.** One causal chain, ending at something observed. If the evidence does
   not reach a cause, say which check was inconclusive rather than naming a plausible
   cause.
3. **Confidence.** `High` only when the health message and the underlying resource
   agree and you verified the cause directly. `Medium` when the cause is strongly
   implied but a step was unverifiable. `Low` when you are reasoning from the status
   alone, or could not reach a resource.
4. **Whether action is required.** Several sustained-unhealthy states are not
   actionable: a resource waiting on something external, a long-running Job, a workload
   inside its progress deadline, a node drain. If nothing should be changed, say so
   explicitly and give the diagnosis alone. Proposing a remediation for a condition
   that resolves itself is worse than proposing nothing.

Shaping a remediation plan — exact commands, risk, reversibility, rollback — is a
separate concern from triage. Do not invent `kubectl` fixes here, and in particular do
not propose one without first checking `spec.syncPolicy.automated.selfHeal`: with
self-heal on, Argo CD reverts a manual cluster change within seconds.

## Reference

| Topic | File | When to load |
|---|---|---|
| Inline versus application-tree resource health | `resource-health.md` | Before filtering any per-resource health values |
| Degraded: a check reported failure | `health-degraded.md` | Status is `Degraded` |
| Progressing: stuck versus still working | `health-progressing.md` | Status is `Progressing` |
| Missing: desired but not live | `health-missing.md` | Status is `Missing` |
| Unknown: health could not be computed | `health-unknown.md` | Status is `Unknown` |
| Application **sync state** triage | `app-sync-triage.md` | The symptom is `OutOfSync`, a stuck or failed sync, or `Synced` while the cluster is wrong. Health and sync are independent — an app can be `Synced` and `Degraded` |
| Operator-owned behavior — destination RBAC, apps-in-any-namespace, and UI RBAC | `operator-troubleshooting.md` | A sync is `forbidden` and resources never appeared, or the Application is ignored entirely |
| Generic Application, ApplicationSet, and Rollout debugging | `../SKILL.md` | The symptom is not an Application health status |
