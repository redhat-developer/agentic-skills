<!-- Loaded on demand by app-sync-triage.md when
     operationState.phase is Running or Terminating. Read-only. -->

# A sync that will not finish

Phase `Running` with no end in sight. Argo CD is waiting for something. Check the
installed version's effective sync timeout: in 3.4,
`controller.sync.timeout.seconds` defaults to `0` (disabled). Retry policy controls
retries after failure; it is not a deadline for a still-running operation. A client
wait timeout is not evidence that the controller terminated the operation.

First, confirm it is actually stuck rather than slow.

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath=''\
'phase={.status.operationState.phase}{"\n"}'\
'message={.status.operationState.message}{"\n"}'\
'startedAt={.status.operationState.startedAt}{"\n"}'\
'retryCount={.status.operationState.retryCount}{"\n"}'
date -u +%Y-%m-%dT%H:%M:%SZ
```

Hooks and multiple waves can extend a sync. Judge progress from current resource
evidence and expected deadlines, not a fixed grace period.

## 1. Find the wave or hook it is waiting on

A sync runs in phases — `PreSync`, `Sync`, `PostSync` — and within each phase in wave
order. The gate depends on sync completion, hook phase and health assessments for
resources that have them. An assessed resource that never becomes healthy can block
advancement until a configured timeout or termination; a kind without a health check
is not inherently a blocker.

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='{range .status.operationState.syncResult.resources[*]}{.hookPhase} {.status} {.kind}/{.name} {.message}{"\n"}{end}'
```

Keep result `.status` (such as `Synced`/`SyncFailed`) separate from `.hookPhase`
(`Running`/`Succeeded`/`Failed`). Empty status is not proof of blocking. Correlate
operation message, hook phase and resource-health evidence to identify the blocked
wave, then read its annotation:

```bash
$KCTL get <kind> <name> -n <ns> \
  -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/sync-wave}{"\n"}'
```

Successful apply does not prove an earlier wave can advance. While an assessed
Deployment remains `Progressing`, it can block the next wave; `Degraded` can fail the
operation instead. The final wave of non-hook tasks can complete without waiting for
health, so verify which gate actually applies. For a workload blocker, read the matching
health leaf in `../SKILL.md`, or `app-health-triage.md` when assessment is unresolved.
Reuse the health snapshot.

`SkipHealthCheck=true` in the desired resource's `argocd.argoproj.io/sync-options`
annotation can complete a non-hook task after apply. It is absent in 3.4; verify
support only when present. Do not enable it to hide unhealthy workloads.

## 2. Hooks

A `PreSync` hook Job that never completes blocks everything after it, and hook failures
do not show up in Application health at all — hooks are excluded from the health
rollup, so the only evidence is here.

```bash
$KCTL get job <hook-job> -n <ns> -o jsonpath='uid={.metadata.uid} active={.status.active} succeeded={.status.succeeded} failed={.status.failed}{"\n"}conditions={.status.conditions}{"\n"}'
$KCTL get pods -n <ns> -l batch.kubernetes.io/controller-uid=<job-uid>
```

| Shape | Cause |
|---|---|
| Job exists, pod `Pending` | Unschedulable, missing PVC, missing image pull secret. Read the pod events. |
| Job exists, pod running forever | The hook command does not terminate. A migration waiting on a lock is the classic case. |
| Job absent entirely | Check operation results and hook deletion policy: creation failure, successful cleanup and hook replacement differ. Absence alone does not establish failed creation. |
| Job from a previous run still present | Inspect its hook deletion policy, deletion timestamp, finalizers and controller errors. An unset policy defaults to `BeforeHookCreation`; absence of the annotation alone does not explain a name collision. |

A retrying hook Job can hold the operation while backoff/runtime accumulate. Inspect
its conditions, retry/backoff limits and any active deadline; there is no fixed
`backoffLimit × pod runtime` deadline.

## 3. Resources that can never become healthy

These can block an early wave when the operation actually waits on their assessment:

- A tracked or hook `Job` meant to run forever. A CronJob's descendant Job is not
  automatically a resource in the Application's sync wave.
- A PVC in `Pending` because no volume can be bound — `WaitForFirstConsumer` with no
  consumer in that wave is a self-deadlock.
- A `Service` of type `LoadBalancer` with no controller to assign an address.
- A custom resource whose configured health assessment waits for operator-populated
  status. Without an assessment, the resource is skipped rather than gating on health.

```bash
$KCTL get pvc <claim> -n <ns>
$KCTL get events -n <ns> --field-selector involvedObject.uid=<blocked-resource-uid> --sort-by=.lastTimestamp | tail -30
```

The tell is that the resource is applied, unchanged, and quiet — no errors anywhere,
the sync simply never advances.

## 4. Terminating

Phase `Terminating` means a sync was asked to stop. If it persists, the operation is
waiting on a resource it cannot finish with.

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='{.status.operationState.message}{"\n"}'
```

If the Application also has a deletionTimestamp, investigate cascade deletion
separately from sync termination. Verify its resource finalizer, remaining children
and controller errors before attributing the wait to a child finalizer:

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='deletionTimestamp={.metadata.deletionTimestamp}{"\n"}finalizers={.metadata.finalizers}{"\n"}'
```

Report the finalizer and which object holds it. Do not strip a finalizer as part of
triage: it orphans live resources and is the kind of action that needs a human who
understands what will be left behind.

## 5. The controller stopped working on it

A sync can also appear stuck because nothing is driving it.

```bash
$KCTL get pods -n "$NS" -l "$CONTROLLER_SELECTOR"
$KCTL logs "$CONTROLLER_POD" -n "$NS" -c "$CONTROLLER_CONTAINER" --since=15m --tail=200 | grep -i -E "$APP|panic|OOM|leader"
```

If `startedAt` predates the controller pod's start time, a restart overlapped the
operation. That timing alone does not establish a stalled controller: reconciliation
may have resumed. Correlate current logs, resource progress and repeated status
observations before attributing the blocker to the controller.

Correlate current OOM/restart failures with the affected controller shard and
Applications. Report that scope while preserving independently observed faults.
`../../argo-performance-tuning/SKILL.md` covers controller sizing and sharding.

## 6. Report

Name the exact resource the operation is waiting on, its phase and wave, and why it
cannot progress. "The sync is stuck" is not a diagnosis; "the sync is in `PreSync`
waiting on Job `db-migrate`, whose pod has been `Pending` for 40 minutes with
`FailedScheduling: insufficient memory`" is.

State whether the blocker is the sync machinery or an unhealthy workload. If it is a
workload, explain the verified gate and continue the relevant health leaf; use
`app-health-triage.md` only when status selection is unresolved.

Sources: [Argo CD 3.4 controller parameters](https://github.com/argoproj/argo-cd/blob/release-3.4/docs/operator-manual/argocd-cmd-params-cm.yaml)
and [hook lifecycle](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/sync-waves/#hook-lifecycle-and-cleanup).
