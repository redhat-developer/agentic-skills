# OutOfSync

Desired and live state differ. Reuse the current-run Application snapshot and inspect
only missing evidence. An `error setting app health` condition routes directly to
`health-unknown.md` and does not invalidate a separately computed diff. Other
comparison errors use `sync-comparison-error.md`; a running operation uses
`sync-stuck.md`. Independent health faults keep their own branch.

## 1. Effective automation and last operation

Read these together if not already known:

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath=''\
'automated={.spec.syncPolicy.automated}{"\n"}'\
'phase={.status.operationState.phase} finished={.status.operationState.finishedAt}{"\n"}'\
'comparedRevision={.status.sync.revision} comparedRevisions={.status.sync.revisions}{"\n"}'\
'operationRevision={.status.operationState.syncResult.revision} operationRevisions={.status.operationState.syncResult.revisions}{"\n"}'\
'operation={.status.operationState.operation.sync}{"\n"}'
```

- Absent `automated` or `automated.enabled: false`: auto-sync is disabled, even when
  `prune`/`selfHeal` are true. An intentionally manual-sync app can remain OutOfSync.
- `automated: {}` or omitted/null `enabled` within the object: auto-sync is enabled.
- `Succeeded` describes that operation, not current convergence. Compare its revision
  or ordered multi-source revisions with the current desired comparison. A new Git
  revision, selective sync, skipped prune or changed parameters can explain the diff
  without a competing writer. Read the resource results before attributing a rewrite.

If disabled automation fully explains this sync symptom, report the configured policy
without recommending enablement. Continue independent health/operator failures and
any specifically requested drift investigation. Do not call an empty operation history
proof that no earlier deployment ever occurred.

Source: [Argo CD 3.4 auto-sync](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/auto_sync/).

## 2. Identify the actual difference

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath=''\
'{range .status.resources[?(@.status!="Synced")]}{.group}/{.kind}/{.namespace}/{.name} comparison={.status}{"\n"}{end}'\
'{range .status.operationState.syncResult.resources[*]}{.group}/{.kind}/{.namespace}/{.name} result={.status} hookPhase={.hookPhase}: {.message}{"\n"}{end}'
```

`.status.resources[].status` holds comparison values (`Synced`, `OutOfSync`,
`Unknown`). `PruneSkipped` belongs to `.status.operationState.syncResult.resources[]`,
not that comparison list. Retain the operation timestamp when interpreting it.

If the Argo CD CLI session is available and targets the correct instance:

```bash
argocd app diff "$APP" --app-namespace "$APP_NS"
```

Return the relevant resource/field differences; if output is limited, disclose that
and retrieve omitted portions needed for the diagnosis. Do not treat a nonzero diff
exit as a connection failure without inspecting the output. Do not retry an already
known broken core-mode connection.

Without a diff, compare the specific live fields against accessible **rendered desired
state at the relevant revision**, not an arbitrary repository file. Use JSONPath or
filtered JSON for those fields. If desired state is unavailable, report that limitation;
a resource status list alone does not identify the differing field or its writer.

## 3. Auto-sync enabled but no operation starts

Inspect targeted current controller decisions only if policy/results do not already
explain the state. Use the observed controller pod/container:

```bash
$KCTL logs "$CONTROLLER_POD" -n "$NS" -c "$CONTROLLER_CONTAINER" --since=15m --tail=200 \
  | grep -F "$APP"
```

Correlate namespace and timestamps, not just a name substring. Expand the time window
for an older incident; an empty filtered tail does not prove the app is unwatched.

| Observed decision | Interpretation |
|---|---|
| `Skipping auto-sync: failed previous sync attempt to <last-revisions> and will not retry for <desired-revisions>` | Prior failure for this revision/parameter combination. Check retry policy and `sync-failed.md`; the final argument is revisions, not a timeout. |
| `Skipping auto-sync: most recent sync already to <rev>` | Prior success with self-heal disabled; not a failed-attempt message. |
| Sync-window block | Evaluate matching windows below; not necessarily an active deny window. |
| Application is deleting | Correlate its deletionTimestamp and operation evidence. |
| No relevant activity | Check freshness, controller/shard ownership and source watching only after ruling out incomplete logs and expected polling policy. |

Use the project name from the snapshot:

```bash
$KCTL get appprojects.argoproj.io "$PROJECT" -n "$NS" -o jsonpath='{.spec.syncWindows}{"\n"}'
```

Evaluate application/namespace/cluster selectors, schedule, timezone and duration.
A matching active deny window can block sync; when matching allow windows exist,
being outside them can also block it. Manual-sync exceptions are separate; inspect
`manualSync` and effective window evaluation rather than inferring all manual behavior
from one window. Report intentional scheduling as working as configured.

For evidence that an operator-managed instance is not watching this Application,
read `operator-apps-in-any-namespace.md`. The destination grant is a different layer.

## 4. Revision and freshness

Reuse compared and operation revision(s). If source targets are unknown:

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath=''\
'single: repo={.spec.source.repoURL} target={.spec.source.targetRevision} path={.spec.source.path} chart={.spec.source.chart}{"\n"}'\
'{range .spec.sources[*]}source: repo={.repoURL} target={.targetRevision} path={.path} chart={.chart} ref={.ref}{"\n"}{end}'\
'observedAt={.status.reconciledAt}{"\n"}'
```

With nonempty `sources`, preserve source order and use `status.sync.revisions[]` and
operation `syncResult.revisions[]`. A values-only source can change the desired render.
A compared revision is not proof it was deployed. A pinned SHA/tag or chart version
can explain why a different branch-head change is irrelevant. Caches and refresh
policy can delay resolution of a changed branch/tag; corroborate before blaming cache.

Read effective `timeout.reconciliation` and `timeout.reconciliation.jitter` only for a
freshness question. In 3.4 the defaults are 120s plus up to 60s jitter; polling can be
customized or disabled. Check expected webhook delivery and controller activity before
calling an older `reconciledAt` a fault. Do not mutate refresh annotations in diagnosis.
Source: [Argo CD 3.4 polling](https://argo-cd.readthedocs.io/en/release-3.4/faq/).

## 5. Same desired inputs, repeated field difference

Enter this branch only after identifying the differing field and ruling out a new
revision, selective operation and pruning. Possible causes:

- **Admission mutation or another writer.** Correlate the actual field change with
  webhook/controller evidence. A list of webhook names alone does not prove causation.
  If another controller legitimately owns the field, consider narrowly scoped
  Application `spec.ignoreDifferences`; instance-wide operator
  `.spec.resourceIgnoreDifferences` has a wider impact. Confirm the installed schema.
  Otherwise correct the conflicting desired input/controller configuration. Do not
  hide an unexplained difference with a blanket ignore rule.
- **Server-side apply.** Argo CD 3.4 uses `--server-side --force-conflicts`. Another
  entry in managedFields alone does not prove apply was rejected. Require the actual
  operation error, or evidence of a subsequent rewrite. Read only relevant manager/path
  information when needed; do not dump all managedFields routinely.
- **Diff ignored but sync overwrites.** `RespectIgnoreDifferences=true` makes sync
  honor ignored fields for existing resources. Without it, a sync can overwrite such
  a field. That does not alone make the ignored field appear OutOfSync: identify any
  unignored difference before claiming it explains Application status flapping.
- **Nondeterministic render.** Compare rendered output at the same inputs for generated
  timestamps or random values. A `helm.sh/hook` annotation alone proves no randomness.

Project `spec.ignoreDifferences` and `spec.syncPolicy.syncOptions` together only when
this branch needs them. See [3.4 sync options](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/sync-options/).

## 6. Pruning

Inspect the actual operation's `PruneSkipped` message and prune option. Automated
pruning defaults off; resource `argocd.argoproj.io/sync-options: Prune=false` can also
retain a resource. `IgnoreExtraneous` suppresses an extraneous resource's contribution
to aggregate sync status; it does **not** prevent deletion or explain `PruneSkipped`.
Source: [compare options](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/compare-options/).

Report deliberate retention as policy. Recommending pruning requires an inventory of
affected tracked live-only resources and dependents; it can delete workloads/data.
Do not enable it or run a sync as diagnosis.

## 7. Report

State the evidenced cause, whether it is a fault, and what remains unverified. Manual
sync, closed windows and intentional retention can require no repair. A demonstrated
competing writer needs its owning configuration corrected; another sync alone will
not remove that cause. Keep independent health/operator findings in the final report.
