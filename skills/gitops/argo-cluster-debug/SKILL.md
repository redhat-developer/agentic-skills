---
name: argo-cluster-debug
description: >
  Debug and troubleshoot Red Hat OpenShift GitOps on live clusters — inspects Argo CD
  Application sync status, health checks, and controller logs; diagnoses Argo Rollouts
  canary/blue-green failures and AnalysisRun results; and handles multi-instance,
  operator-managed installs. Use for Degraded, Progressing, Missing or Unknown health,
  OutOfSync, stuck or failed syncs, Synced-but-wrong resources, permission errors
  (forbidden/Unauthorized), or Applications ignored with no status or missing from the
  UI. Supports unattended diagnosis of sustained unhealthy or OutOfSync status.
  Argo Workflows and Argo Events are out of scope.
license: MIT
compatibility: Requires oc or kubectl; optionally argocd and kubectl-argo-rollouts
---

# Argo Cluster Debug

Debug Argo CD and Argo Rollouts on live Kubernetes and OpenShift clusters.

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| `kubectl` **or** `oc` | Yes | CRD inspection, pod logs, resource status |
| argocd | No | Richer Application output, diff, sync operations |
| kubectl-argo-rollouts | No | Rollout status, step details, promotion |

**Resolve the CLI before any workflow. On OpenShift, `oc` is the default.**

```bash
# Detect the platform and pick the CLI — on OpenShift, oc is the default.
if command -v oc >/dev/null 2>&1 && oc api-resources --api-group=route.openshift.io 2>/dev/null | grep -q routes; then
  KCTL=oc; PLATFORM=OpenShift
elif command -v kubectl >/dev/null 2>&1; then
  KCTL=kubectl
  PLATFORM=$(kubectl api-resources --api-group=route.openshift.io 2>/dev/null | grep -q routes && echo OpenShift || echo Kubernetes)
elif command -v oc >/dev/null 2>&1; then
  KCTL=oc; PLATFORM=Kubernetes
else
  echo "ERROR: no cluster CLI found — install kubectl or oc" >&2; exit 1
fi
echo "Platform: $PLATFORM — using '$KCTL'"

# Resolve the Argo CD namespace too — `argocd` is the upstream default and is almost
# never right on OpenShift, where it is `openshift-gitops` (and often several instances).
$KCTL get argocd -A --no-headers 2>/dev/null || \
  $KCTL get pods -A -l app.kubernetes.io/part-of=argocd --no-headers 2>/dev/null | awk '{print $1}' | sort -u
NS=openshift-gitops      # set to the instance you are working on; every command below uses $NS
```

Every `kubectl` in these workflows means `$KCTL`. Prefer `oc` on OpenShift for Routes,
SCCs and `oc adm`. Report a missing prerequisite only when neither CLI exists.
Discover operator-managed `ArgoCD` CRs (`argoproj.io/v1beta1`) and their namespaces.

## How This Skill Works

Follow the selected workflow from symptoms to an evidence-backed root cause.

**Before starting any workflow:**
1. Resolve `oc` or `kubectl` and any optional CLI needed for the selected workflow.
2. Confirm the cluster context and identify the owning instance and resource. Always
   use `applications.argoproj.io`; short names can select a different CRD on ACM
   clusters. If a lookup is empty or returns NotFound, load `references/resource-lookup.md`.
3. Establish installation health with Workflow 1 when it is not already known. Reuse
   evidence from the current run; do not repeat a full installation survey at each handoff.
4. Pick the matching route below and load only its reference. Routers select their
   own leaf files. Use `references/troubleshooting.md` only for an inconclusive check
   or a symptom outside the dedicated triage routes.

**General rules:**
- Prefer specialized CLIs when available; fall back to `oc`/`kubectl` for inspection.
- Diagnosis is read-only. Only explicitly requested Rollout control can write, below.
- Read conditions, health, sync status and operation phase as distinct signals.
- Complete the selected workflow, including secondary findings. A handoff continues
  the same diagnosis with the gathered evidence; do not restart the generic workflow.
- For an unattended run, do not ask questions or wait for input. Gather accessible
  evidence, state confidence and unavailable checks, and report unresolved ambiguity.
  Investigate candidate instances separately; never silently substitute a resource.
- A denied read is unavailable evidence, not proof an object is absent. Continue with
  accessible checks; do not retry unchanged denials or seek extra privileges in diagnosis.
- Shell calls may start fresh: set `KCTL`, `NS`, `CR`, `APP` and `APP_NS` in each call
  that uses them, or combine dependent commands in one call. `APP_NS` is the Application
  object's namespace; `NS` is the owning Argo CD instance's namespace.

## Writes: Rollout control only

Diagnosis is read-only. This skill performs exactly one class of write — **Argo Rollouts
runtime control: promote, abort, retry** — because a Rollout's progression is runtime
state that no controller owns and Git cannot express. Pausing at step 2 awaiting
promotion is not drift; it is the Rollout doing its job.

Everything else stays out:

| Request | Why not, and what to do |
|---|---|
| Create/edit an Application, ApplicationSet, AppProject | Desired state belongs in Git. Hand back the manifest to commit; applying it directly produces the drift Argo CD exists to prevent. |
| Install, configure or upgrade Argo CD | The OpenShift GitOps Operator's job. Point at the Subscription/CSV. |
| Rotate repository credentials | Belongs in External Secrets Operator / Vault / Sealed Secrets — see `../argo-knowledge/references/openshift-gitops-operator.md`. |
| Tune performance settings | → `argo-performance-tuning` |

**Every permitted Rollout write follows
the shared protocol in [`../write-safety.md`](../write-safety.md): Generate → Preview →
Blast radius → Confirm → Verify.** Destructive operations additionally require the user
to type the resource name; "yes" alone is not sufficient.

Verify a Rollout action by its **resulting phase**, not by the command returning:

```bash
kubectl argo rollouts get rollout <name> -n <ns>
# or, with no plugin:
$KCTL get rollouts.argoproj.io <name> -n <ns> \
  -o jsonpath='phase={.status.phase} step={.status.currentStepIndex} msg={.status.message}{"\n"}'
```

## Cluster Context

- If the user specifies a cluster context, switch to it:
  ```bash
  kubectl config use-context <context-name>
  ```
  If using argocd CLI with a remote server:
  ```bash
  argocd context <context-name>
  ```
- If no cluster is specified, use the current context. Confirm it:
  ```bash
  kubectl config current-context
  ```
- Verify the owning installation before Application/ApplicationSet debugging; reuse
  current-run evidence. Discover the actual namespace rather than assuming `argocd`.

## Debugging Workflows

Workflows 1–5 live in `references/debug-workflows.md`; Workflow 6 is below.
For Applications, select 2a, 2b, 2c or generic Workflow 2, then load its reference.

| # | Workflow / reference | Use when |
|---|---|---|
| 1 | Installation check — `references/debug-workflows.md` | General Argo CD failure, installation check, or owning installation health is unverified |
| 2a | Health — `references/app-health-triage.md` | Application health is `Degraded`, sustained `Progressing`, `Missing`, or `Unknown` |
| 2b | Sync — `references/app-sync-triage.md` | `OutOfSync`, sync `Unknown`, comparison errors, stuck/failed operations, or `Synced` while the cluster is wrong |
| 2c | Operator inputs — `references/operator-troubleshooting.md` | Operator-managed instance: sync `forbidden`/`Unauthorized`, ignored Application with no status, source-namespace rejection, or UI access lost after moving Applications |
| 2 | Generic Application — `references/debug-workflows.md` | Other Application questions, including intentional suspension; use the triage routes above for health/sync/operator symptoms |
| 3 | ApplicationSet — `references/debug-workflows.md` | Missing/wrong generated Applications, generator errors, or progressive sync failures |
| 4 | Rollout — `references/debug-workflows.md` | Canary/blue-green stuck, aborted or degraded; requested promote, abort or retry |
| 5 | Logs — `references/debug-workflows.md` | Cross-component log correlation when the failing component is unknown |
| 6 | Operator / OLM — below | Upgrade wedged, operator crash-looping, conversion webhook failing, or correct operator input never reconciled |

For overlapping symptoms, route explicit operator-owned permission or watch failures to
2c. Otherwise investigate comparison/operation errors through 2b, then use 2a for a
workload health blocker. `Synced` plus `Degraded` is a health problem; `OutOfSync` plus
`Degraded` requires both signals checked. Keep one causal chain and distinguish
independent findings. If the input is correct for a supported instance scope but
generated objects are absent, investigate reconciliation through Workflow 6.

### Workflow 6: Operator / OLM triage (OpenShift GitOps)

Not an Argo CD problem but an *operator* problem, and it masquerades as one. Symptoms:
CR edits revert, a new setting never takes effect, components run an old version, or
everything is "Available" while nothing you change sticks.

```bash
# 1. Is the operator itself healthy? Restart count is the tell.
oc get pods -n openshift-gitops-operator

# 2. CSV phase is authoritative. The Subscription's `state` is NOT — it reports
#    AtLatestKnown while the CSV behind it is stuck Pending or Replacing.
oc get csv -n openshift-gitops-operator -o custom-columns=NAME:.metadata.name,PHASE:.status.phase
oc get subscriptions.operators.coreos.com -n openshift-gitops-operator \
  -o jsonpath='installedCSV={.items[0].status.installedCSV} state={.items[0].status.state}{"\n"}'

# 3. A failed InstallPlan is the usual blocker
oc get installplan -n openshift-gitops-operator \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase
oc describe installplan -n openshift-gitops-operator | grep -A5 -i 'message\|condition'

# 4. Conversion webhook — an empty caBundle or a crash-looping operator pod makes every
#    ArgoCD CR write fail admission, which looks like "my edits revert"
oc get crd argocds.argoproj.io \
  -o jsonpath='{.spec.conversion.webhook.clientConfig.caBundle}{"\n"}' | wc -c
```

**A zero-length `caBundle`, or an operator pod with hundreds of restarts, means the
operator cannot reconcile anything.** Fix that before investigating any Argo CD symptom
downstream of it — otherwise you are debugging the shadow.

Run **Workflow 1 first** whenever Argo CD's own health is unverified in this run — a broken controller
or repo-server explains most Application-level symptoms, and skipping it leads to
misdiagnosing a healthy Application as broken.

## Report Format

Every session ends with an evidence-backed report, including the selected router's
Output/Report requirements. Use `references/report-format.md` for Markdown. When the
caller supplies an output schema, load `references/runtime-output.md` instead and
follow that schema's fields and types. Report confidence, unavailable checks, whether
action is required, and recommendation impact; separate findings by instance. Operator
triage must establish instance scope and the grant or source-namespace layer. Do not
invent remediation for working-as-configured states. Proposed commands do not authorize
execution; diagnosis remains read-only.

## Edge Cases

Handle these scenarios explicitly:

| Scenario | Behavior |
|----------|----------|
| Argo CD not installed (no argocd namespace or CRDs) | Report "Argo CD is not installed on this cluster" and stop Application/AppSet workflows |
| argocd CLI not logged in | Detect `{"level":"fatal","msg":"Argo CD server address unspecified",...}` (JSON, not a literal `FATAL:` prefix — grep for `\"level\":\"fatal\"` or just `fatal`) and suggest `argocd login <server>` |
| **The named resource does not exist** | Do not invent findings and do not silently debug a different object. Load `references/resource-lookup.md` and report what you searched. Ask for the right name only in an interactive session; unattended runs report the unresolved target |
| Multiple Argo CD instances | Report **per instance** (see Report Format) rather than asking the user to choose — multiple instances are the norm on OpenShift. Ask only if a *write* is required and the target is ambiguous |
| Application in Progressing state | Use Workflow 2a. Inspect pods and progress evidence; `Progressing` alone does not prove healthy reconciliation, even within a Deployment's progress deadline |
| Suspended Application or Rollout | Report as intentional suspension, do not treat as error unless user says otherwise |
| Unknown health status | Check for custom health check Lua scripts in `argocd-cm` under `resource.customizations.health.<group_kind>` |
| Rollout without traffic management | Note that canary is replica-based only — weight percentages are approximated by replica ratio |
| Helm source with missing values files | Check `spec.source.helm.valueFiles` paths relative to the chart, not the repo root |
| Multi-source Application | Iterate all entries in `spec.sources[]` — each source can fail independently |

## Argo CRD Reference

All CRDs use `apiVersion: argoproj.io/v1alpha1` unless noted:

| Kind | Project | Description |
|------|---------|-------------|
| Application | Argo CD | Defines a deployed application |
| AppProject | Argo CD | Groups applications with RBAC and restrictions |
| ApplicationSet | Argo CD | Templated multi-cluster/multi-env application generation |
| Rollout | Argo Rollouts | Advanced deployment with canary/blue-green |
| AnalysisTemplate | Argo Rollouts | Metrics-based promotion criteria |
| ClusterAnalysisTemplate | Argo Rollouts | Cluster-scoped AnalysisTemplate |
| AnalysisRun | Argo Rollouts | Instance of an analysis execution |
| Experiment | Argo Rollouts | Temporary ReplicaSet for A/B testing |

## Reference Index

| Topic | Reference File | When to Load |
|---|---|---|
| Installation, generic Application, ApplicationSet, Rollout and log workflows | `references/debug-workflows.md` | Workflow 1–5 when selected; Application triage uses its router |
| Symptom → cause tables | `references/troubleshooting.md` | A selected workflow is inconclusive; dedicated triage routers own health/sync rules |
| Application health rollup and status triage | `references/app-health-triage.md` | Workflow 2a, including automated unhealthy-status diagnosis |
| Application diff and sync-operation triage | `references/app-sync-triage.md` | Workflow 2b, including automated OutOfSync diagnosis |
| Destination RBAC and apps-in-any-namespace | `references/operator-troubleshooting.md` | Workflow 2c; diagnose operator inputs without writing generated RBAC or ConfigMaps |
| Missing resources and ambiguous CRD short names | `references/resource-lookup.md` | Lookup is empty or NotFound |
| Evidence, per-instance findings and recommendation impact | `references/report-format.md` | Before producing a Markdown report |
