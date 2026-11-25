<!-- Loaded on demand by app-health-triage.md when the
     Application health status is Unknown. Read-only. -->

# Unknown

Argo CD has no established healthy/unhealthy verdict. An assessment may have failed,
returned `Unknown` deliberately, or the controller may lack comparison evidence.
Distinguish those cases from the actual condition message; do not assume a Lua defect.
For example, the built-in Pod/PVC checks can return `Unknown` without an evaluation
error when their phase is unrecognized or not yet populated.

## Why this status is special

`Unknown` is the **worst** status in the rollup order:

`Healthy` → `Suspended` → `Progressing` → `Missing` → `Degraded` → `Unknown`

One resource whose assessment counts in the rollup can therefore make the Application
`Unknown`, masking lower-ranked failures in its aggregate status. An Application can be `Unknown` while a Deployment
inside it is in `CrashLoopBackOff`; the crash loop is invisible at app level.

Two implications for triage:

1. Identify why the verdict is `Unknown`; recommend a correction only for a verified
   fault. Continue independent findings without waiting for remediation.
2. Review the complete successful resource-health snapshot for masked faults. Reuse it
   rather than fetching it again merely because the investigation changed branches.

A child `Application` that is `Unknown` is excluded from its parent in an app-of-apps,
so that child alone does not explain the parent's `Unknown`. The parent may have
another unknown resource or a comparison-level failure.

## 1. Find the resource and read its message

Use the successful snapshot from `resource-health.md` and select explicit
`Unknown` assessments. Retain the resource identity and health message. If resource
health is unavailable, inspect accessible live conditions and report the evidence gap;
an empty inline field is not an assessment.

**The health message carries the error text.** When a custom Lua script fails, Argo CD
sets the status to `Unknown` and puts the script's error in the message — a Lua
runtime error, a nil index, a type error. Quote it and identify the failing expression
and missing/mistyped field before proposing a correction.

Reuse Application conditions and health from the existing snapshot. If unavailable,
read them together; aggregate `.status.health.message` alone may omit assessment
errors, which are recorded in `.status.conditions`:

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='health={.status.health.status}: {.status.health.message}{"\n"}{range .status.conditions[*]}condition={.type}: {.message}{"\n"}{end}'
```

`ComparisonError` with `error setting app health: ...` belongs to this assessment
procedure; it does not establish a manifest-rendering or repository failure. Other
comparison messages go to `sync-comparison-error.md` when independently present.
Retain the current sync status and operation evidence; do not reclassify them solely
from the condition type. A failed comparison can yield aggregate `Unknown` without
any individual resource assessment.

## 2. Custom health script errors

When the message identifies an assessment error, check the applicable override:

```bash
# Example key; substitute the implicated group/kind.
$KCTL get cm argocd-cm -n "$NS" -o jsonpath='{.data.resource\.customizations\.health\.example\.com_Widget}{"\n"}'
```

The key is `resource.customizations.health.<group>_<Kind>`. For a core-group kind the
key is kind-only, for example `resource.customizations.health.Pod` (no underscore).
If the split key is absent, inspect the relevant legacy `resource.customizations`
entry or bundled script; absence of a split key is not proof no assessment exists.

Nested indexing or iteration over absent/mistyped fields can fail: status may not
exist yet, conditions may be absent, or an API version may have changed the schema.
Compare the actual failing expression and object; other healthy instances of the
same kind are supporting evidence, not proof of this cause. If the script returns
`Unknown` normally, investigate the condition it is waiting for rather than treating
the return value as a Lua exception.

Compare the script's assumptions against the live object:

```bash
$KCTL get <kind> <name> -n <ns> -o jsonpath='{.status}'
```

A verified override defect belongs in its authoritative configuration. On an
operator-managed instance, use the supported `ArgoCD.spec.resourceHealthChecks` input
through Git; a direct generated `argocd-cm` edit can be reverted. If the assessment
correctly reports missing workload/controller status, repair that underlying cause.

## 3. The controller cannot reach the destination cluster

When conditions identify cluster connectivity, credentials or cache errors, correlate
other Applications using that destination. Shared failures can implicate the
connection, but can also come from a shared override; scope alone does not decide.
Reuse conditions and destination evidence already collected; request only missing
identity fields or cluster-secret server metadata below.

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='server={.spec.destination.server}{"\n"}name={.spec.destination.name}{"\n"}'

$KCTL get secrets -n "$NS" -l argocd.argoproj.io/secret-type=cluster \
  -o jsonpath='{range .items[*]}{.metadata.name} {.data.server}{"\n"}{end}'

```

Use the actual connection/authentication error in conditions or current controller
logs. An expired credential can affect Applications using that destination, but
reconciliation timing and cached state vary. Do not infer credential failure from
`Unknown` alone or retrieve cluster credential values.

## 4. The kind disappeared

A removed served API version or stale cached resource inventory can cause discovery
errors. Deleting a CRD also deletes its custom resources; do not assume they survive
as readable live CRs. Correlate discovery and comparison errors with the exact version.

```bash
$KCTL api-resources 2>&1 | grep -i <kind>
$KCTL get crd <plural>.<group> -o jsonpath='{range .spec.versions[*]}{.name} served={.served}{"\n"}{end}'
```

A version that is no longer `served` while manifests still request it produces errors
on every reconcile.

## 5. Controller health

Current controller or cache failures can prevent fresh assessment and leave stale
status. Establish readiness, restart timing and error evidence before attributing an
`Unknown` status to controller failure.

```bash
$KCTL get pods -n "$NS" -l "$CONTROLLER_SELECTOR"
$KCTL logs "$CONTROLLER_POD" -n "$NS" -c "$CONTROLLER_CONTAINER" --since=15m --tail=100 | grep -i -E "error|failed to get resource health"
```

The log line `failed to get resource health for "<Kind>" with name "<name>" in
namespace "<ns>"` wraps assessment errors, including invalid Lua; it is **not** evidence
of controller OOM or wedging by itself. Read its nested cause. See
[assessment error handling](https://github.com/argoproj/argo-cd/blob/release-3.4/controller/health.go) and
[Application condition handling](https://github.com/argoproj/argo-cd/blob/release-3.4/controller/state.go).

If current controller failure explains the affected shard/instances, report that
scope without dropping independently observed workload faults. Historical restarts
alone do not prove an ongoing outage. `../../argo-performance-tuning/SKILL.md`
covers controller sizing.

## 6. Report

State the verified cause or remaining uncertainty and quote the supporting message.
Then state which independent faults were observed:

Review the successful `resource-health.md` snapshot for explicit unhealthy states
other than `Unknown`. Verify any missing live objects and preserve independent sync
findings. Do not classify empty health fields through a negative grep filter.

If the complete snapshot has no other unhealthy assessments, say that none were
observed. If health retrieval was unavailable, report that limit. Report degraded
workloads and absent live resources separately: a degraded workload may determine
the aggregate after `Unknown` resolves; an individually absent resource does not
lower aggregate health in 3.4.
