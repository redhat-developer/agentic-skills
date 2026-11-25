<!-- Loaded on demand by app-health-triage.md when the
     Application health status is Unknown. Read-only. -->

# Unknown

Health could not be computed. This is almost always a broken **health check**, not a
broken workload — and it is the single most misdiagnosed Argo CD status, because the
natural reading ("something is wrong with my app") is usually false.

## Why this status is special

`Unknown` is the **worst** status in the rollup order:

`Healthy` → `Suspended` → `Progressing` → `Missing` → `Degraded` → `Unknown`

So one resource whose health check errors makes the entire Application `Unknown` and
masks every other problem in it. An Application can be `Unknown` while a Deployment
inside it is in `CrashLoopBackOff`; the crash loop is invisible at app level.

Two implications for triage:

1. Identify the failed assessment and recommend its owning-input correction; do not
   mutate it during diagnosis or wait for remediation to investigate other faults.
2. Review the complete successful resource-health snapshot for masked faults. Reuse it
   rather than fetching it again merely because the investigation changed branches.

A child `Application` that is `Unknown` is excluded from its parent in an app-of-apps,
so a parent reporting `Unknown` has its own unknown resource.

## 1. Find the resource and read its message

Use the successful snapshot from `resource-health.md` and select explicit
`Unknown` assessments. Retain the resource identity and health message. If resource
health is unavailable, inspect accessible live conditions and report the evidence gap;
an empty inline field is not an assessment.

**The health message carries the error text.** When a custom Lua script fails, Argo CD
sets the status to `Unknown` and puts the script's error in the message — a Lua
runtime error, a nil index, a type error. That message is the diagnosis; quote it.

If the Application itself is `Unknown` but no individual resource is, read the
app-level message:

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='{.status.health.status}: {.status.health.message}{"\n"}'
```

A message of the form `see application-controller logs for N other errors; most recent
error was: ...` records multiple assessment errors. Inspect their actual messages;
separate overrides can fail independently, so this alone does not prove a controller fault.

## 2. Custom health script errors

The most common cause. Check whether an override exists for the kind:

```bash
# Example key; substitute the implicated group/kind.
$KCTL get cm argocd-cm -n "$NS" -o jsonpath='{.data.resource\.customizations\.health\.example\.com_Widget}{"\n"}'
```

The key is `resource.customizations.health.<group>_<Kind>`. For a core-group kind the
key is kind-only, for example `resource.customizations.health.Pod` (no underscore).
If the split key is absent, inspect the relevant legacy `resource.customizations`
entry or bundled script; absence of a split key is not proof no assessment exists.

A script errors rather than returning a verdict when it indexes a field that does not
exist on this particular CR — a status subresource that has not been populated yet, a
conditions array that is absent on a freshly created object, or an API version change
that moved a field. The giveaway is that the same kind is healthy elsewhere and only
the new or just-created instances are `Unknown`.

Compare the script's assumptions against the live object:

```bash
$KCTL get <kind> <name> -n <ns> -o jsonpath='{.status}'
```

The remediation lives in `argocd-cm`, not in the workload. Note that editing
`argocd-cm` on an operator-managed instance will be reverted — the override belongs in
the `ArgoCD` CR's `resourceHealthChecks`. Say so rather than suggesting a direct edit.

## 3. The controller cannot reach the destination cluster

If every resource in an Application is `Unknown`, or whole Applications pointing at one
destination are `Unknown`, the cluster connection is the suspect rather than any
script.

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='server={.spec.destination.server}{"\n"}name={.spec.destination.name}{"\n"}'

$KCTL get secrets -n "$NS" -l argocd.argoproj.io/secret-type=cluster \
  -o jsonpath='{range .items[*]}{.metadata.name} {.data.server}{"\n"}{end}'

$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'
```

An expired or rotated cluster credential shows up as `ComparisonError` or
`UnknownError` conditions on every Application using that destination. Check whether
the blast radius is one Application or all of them before diagnosing — that one
observation separates a script bug from a credential problem.

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

Assessment also fails when the application controller is itself unhealthy — out of
memory, wedged, or failing to build the cluster cache.

```bash
$KCTL get pods -n "$NS" -l "$CONTROLLER_SELECTOR"
$KCTL logs "$CONTROLLER_POD" -n "$NS" -c "$CONTROLLER_CONTAINER" --since=15m --tail=100 | grep -i -E "error|failed to get resource health"
```

The log line `failed to get resource health for "<Kind>" with name "<name>" in
namespace "<ns>"` is emitted for exactly this case and names the resource directly.

If current controller failure explains the affected shard/instances, report that
scope without dropping independently observed workload faults. Historical restarts
alone do not prove an ongoing outage. `../../argo-performance-tuning/SKILL.md`
covers controller sizing.

## 6. Report

Name which of the five it is and quote the error text you found. Then state explicitly
what the `Unknown` was hiding:

Review the successful `resource-health.md` snapshot for explicit unhealthy states
other than `Unknown`. Verify any missing live objects and preserve independent sync
findings. Do not classify empty health fields through a negative grep filter.

If the complete snapshot has no other unhealthy assessments, say that none were
observed. If health retrieval was unavailable, report that limit. Report degraded
workloads and absent live resources separately: a degraded workload may determine
the aggregate after `Unknown` resolves; an individually absent resource does not
lower aggregate health in 3.4.
