<!-- Loaded on demand by app-health-triage.md when the
     Application health status is Missing. Read-only. -->

# Missing

Distinguish a resource's `Missing` assessment from the Application's aggregate health.
These rules target Argo CD 3.4; verify the running version for older installations.

## What Missing already tells you

In 3.4, a resource with no live object gets an individual `Missing` assessment, but
that assessment is skipped when rolling health up to the Application. This applies
to every kind, including ConfigMaps, Secrets and health-checkable workloads.

The aggregate becomes `Missing` when non-hook resources are expected and none of
those resources are live. Do not look for a particular missing kind as the explanation.
A ConfigMap-only app with its only resource absent can therefore be `Missing`; a
missing ConfigMap beside a live Deployment cannot explain aggregate `Missing` by
itself. The missing ConfigMap may still break that Deployment's pods.

A live custom health check can explicitly return `Missing` too. If live resources
exist, inspect the actual assessment and override before concluding the aggregate
is stale. A live child Application's `Missing` or `Unknown` status is excluded from
its parent's rollup; that is distinct from the parent having no live objects at all.

Source: [Argo CD 3.4 health aggregation](https://github.com/argoproj/argo-cd/blob/release-3.4/controller/health.go).

## 1. Establish the expected set and live presence

Use `resource-health.md` for inline or tree assessments; missing inline health values
are not evidence of missing objects. Read the full expected resource list, destination
and comparison time:

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='destination={.spec.destination}{"\n"}reconciledAt={.status.reconciledAt}{"\n"}{range .status.resources[*]}{.group}/{.kind}/{.namespace}/{.name} sync={.status}{"\n"}{end}'
```

Check the relevant objects on the actual destination cluster, with the recorded
namespace (or cluster scope), and distinguish a successful `NotFound` lookup from
`Forbidden` or an inaccessible cluster:

```bash
$KCTL get <kind> <name> -n <ns>
```

If any expected object is live, a single deletion cannot explain the normal
all-absent aggregate. Check comparison freshness, custom assessments and whether the
lookup targeted the same cluster. If objects appear absent only to Argo CD, continue
to section 5. If all are absent, establish why sync never created or restored them.

## 2. Did a sync ever run, and did it succeed?

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='phase={.status.operationState.phase}{"\n"}message={.status.operationState.message}{"\n"}finishedAt={.status.operationState.finishedAt}{"\n"}revision={.status.sync.revision}{"\n"}'

$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='{range .status.operationState.syncResult.resources[*]}{.kind}/{.namespace}/{.name} {.status} {.hookPhase} {.message}{"\n"}{end}'
```

| What you see | Cause |
|---|---|
| No `operationState` at all | The Application has never synced. Check `syncPolicy` — a manual-sync app that nobody synced is `Missing` by design, not by fault |
| `phase: Failed` with `forbidden` or `Unauthorized` in a resource message | RBAC. The Argo CD instance may not be permitted in the destination namespace. Load `operator-troubleshooting.md` — the operator owns that grant and it must not be hand-written |
| `phase: Failed`, message naming a kind | Often a CRD that is not installed. Section 3 |
| `phase: Error` on a hook | A `PreSync` hook failed and the sync never reached the resources. The hook itself is excluded from health, so it will not show as unhealthy anywhere |
| `phase: Succeeded`, resource still absent | The object was created and then removed. Section 4 |

## 3. Does the kind exist on the cluster?

A manifest for a kind with no CRD cannot be applied.

```bash
$KCTL api-resources | grep -i <kind>
$KCTL get crd | grep -i <group>
```

A sync that fails only for the CRs, while the operator's own resources are fine, is
usually ordering: the CRD and its CRs went in the same sync wave. Confirm with the
sync result messages rather than assuming.

Also confirm the destination namespace exists — resources cannot be created in a
namespace that is absent or terminating:

```bash
$KCTL get ns <dest> -o jsonpath='phase={.status.phase}{"\n"}deletionTimestamp={.metadata.deletionTimestamp}{"\n"}'
```

## 4. Was it created and then removed?

```bash
$KCTL get events -n <ns> --sort-by=.lastTimestamp | grep -i -E "delete|evict|prune" | tail -20
```

Candidates:

- Someone or something deleted it outside Argo CD. With `selfHeal: false` Argo CD
  reports the drift and leaves it missing.
- An owner was deleted and garbage collection removed this object with it.
- A namespace is terminating.
- Another Application manages the same resource and pruned it. Two Applications
  fighting over one object show as alternating sync and missing states; check whether
  another Application lists the same resource:

```bash
$KCTL get applications.argoproj.io -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
```

Note that `prune` only removes what is no longer in git. A resource still in the
desired state is not pruned, so pruning does not explain a resource that Argo CD still
expects.

## 5. Argo CD cannot see it

If the object exists on the cluster but the Application calls it missing, the cause is
visibility rather than existence:

- **Cluster cache is stale.** A hard refresh re-reads live state. Diagnose it by
  comparing the object's `creationTimestamp` to `.status.reconciledAt`.
- **The destination is a different cluster** than you are inspecting. Check
  `.spec.destination.server` before concluding anything from a local lookup.
- **A resource exclusion** removes the kind from Argo CD's managed set. Instance-wide
  exclusions live in `resource.exclusions` in `argocd-cm`. `ignoreDifferences` suppresses
  field differences; it does not hide the existence of an entire object.
- **Namespace mismatch.** The manifest has no namespace and the destination differs
  from where you looked.

## 6. Report

State which of the five it is, with the sync result or event that shows it. The two
most common correct conclusions:

- The sync failed, and the resource is missing *because* of that failure. The root
  cause is the sync error; the missing resource is the symptom. Do not report them as
  two findings.
- The app has never been synced. There is no fault at all. Say that plainly rather
  than constructing a cause.
