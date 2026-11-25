<!-- Loaded on demand by app-sync-triage.md when
     operationState.phase is Failed or Error. Read-only. -->

# A sync that failed

`Failed` means the operation ran and at least one resource could not be applied.
`Error` means the operation could not be carried out at all. Both leave a message, and
a per-resource result that says exactly which object broke.

Note that a failed sync does **not** make the Application `OutOfSync` on its own — the
status reflects the comparison that followed. An Application reading `Synced` with
phase `Failed` is normal and means the failure did not change the diff.

## 1. Read the per-resource result

The app-level message is a summary. The resource list is the diagnosis.

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='{range .status.operationState.syncResult.resources[*]}result={.status} hookPhase={.hookPhase} {.kind}/{.namespace}/{.name}: {.message}{"\n"}{end}'
```

Do not discard a result just because its apply status is `Synced`: its hook phase can
still be `Failed` or `Error`. Keep the two fields separate when selecting failures.

| Field / value | Meaning |
|---|---|
| `status: SyncFailed` | The apply was rejected. Read the API server or operation message. |
| `status: PruneSkipped` | Not a failure. The resource was left alone deliberately. |
| `hookPhase: Failed` or `Error` | The resource or hook operation failed; inspect its message and live conditions. |

Quote the message. Nearly every cause below is identifiable from its text alone, and
the rest of this file is about what to confirm once you have read it.

For a failed hook, inspect its operation result and the Job/Pod conditions and events.
A failed `PreSync` hook can prevent all normal resources from being created. Read
`health-missing.md` if the Application is `Missing`; read the Pod rules in
`health-degraded.md` before explaining why a hook Pod's waiting reason did not produce
`Degraded`. Hook exclusion from aggregate health and Pod restart-policy rules are
separate mechanisms.

## 2. Classify the message

| Message contains | Cause | Confirm with |
|---|---|---|
| `forbidden`, `Unauthorized`, `cannot create resource` | RBAC. The controller ServiceAccount may not write that kind in that namespace. | Section 3 |
| `is invalid`, `ValidationError`, `unknown field` | The manifest is wrong, or the CRD schema differs from what it was written against. | Section 4 |
| `conflict`, `Operation cannot be fulfilled`, `field is managed by` | Another writer owns the object or the field. | Section 5 |
| `admission webhook ... denied the request` | A policy engine rejected it. The webhook name is in the message. | Section 6 |
| `the server could not find the requested resource` | The CRD is not installed, or the API version was removed. | Section 7 |
| `exceeded quota` | A ResourceQuota in the destination namespace. | Read the quota directly |
| `namespaces "<ns>" not found` | The destination namespace does not exist and `CreateNamespace=true` is not set. | Section 7 |

## 3. RBAC

Two independent layers, and both can reject a sync. Check both; fixing one while the
other is also broken produces a second identical failure.

**Kubernetes RBAC** — can the controller write this object?

```bash
$KCTL auth can-i <verb> <resource> \
  --as=system:serviceaccount:"$NS":"$CR"-argocd-application-controller \
  -n <destination-namespace>
```

On an operator-managed instance this is almost never fixed by writing a Role. The
operator creates the destination-namespace Role and RoleBinding from the
`argocd.argoproj.io/managed-by` label or a `NamespaceManagement` handshake, and a
parallel hand-written binding bypasses that grant lifecycle. Load `operator-rbac.md` before
recommending any RBAC manifest.

A `forbidden` on a **cluster-scoped** kind from a namespace-scoped instance is a
different problem and no label fixes it — a Role cannot grant cluster-scoped resources.

**AppProject policy** — is the resource kind allowed at all?

```bash
PROJ=$($KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath='{.spec.project}')
$KCTL get appproject "$PROJ" -n "$NS" -o jsonpath=''\
'clusterResourceWhitelist={.spec.clusterResourceWhitelist}{"\n"}'\
'namespaceResourceBlacklist={.spec.namespaceResourceBlacklist}{"\n"}'\
'namespaceResourceWhitelist={.spec.namespaceResourceWhitelist}{"\n"}'
```

A project rejection reads differently — it names the project and happens before the API
call — so the message distinguishes the two layers for you.

## 4. Invalid manifests

The API server rejected the object's shape.

```bash
$KCTL get crd <plural>.<group> \
  -o jsonpath='{range .spec.versions[*]}{.name} served={.served} storage={.storage}{"\n"}{end}'
```

Causes worth separating, because they lead to different fixes:

- The manifest is genuinely malformed. A render-time templating bug produces this and
  the repo is where it gets fixed.
- The CRD is an older version than the manifest expects. `unknown field` on a CR
  usually means the operator providing the CRD has not been upgraded.
- A missing-kind dry run was skipped, so an error surfaced only at apply time.
  Argo CD skips that dry run automatically when the CRD is in the same sync.
  `SkipDryRunOnMissingResource=true` does not disable schema validation for a kind
  whose CRD is already installed.

## 5. Conflicts

Another writer holds the object.

```bash
$KCTL get <kind> <name> -n <ns> \
  -o jsonpath='{range .metadata.managedFields[*]}{.manager} {.operation} {.subresource}{"\n"}{end}'
```

| Shape | Cause |
|---|---|
| Another controller in `managedFields` | Identify the rejected field and actual ownership conflict; multiple managers alone are normal. If another writer is authoritative, `ignoreDifferences` changes comparison only. Assess `RespectIgnoreDifferences=true` when sync must also preserve the existing live field. |
| `Operation cannot be fulfilled ... object has been modified` | An optimistic-concurrency retry. Usually transient; if it repeats every sync, something writes the object continuously. |
| An immutable field | Identify the rejected field and kind/version constraint. `Replace=true` does not bypass immutability. Correct the desired change or plan a supported migration; deletion/recreation is a separate destructive action. |

The immutable-field case deserves care in the report: recreating a StatefulSet or a PVC
is data-destructive, and triage should name the constraint rather than recommend the
recreation.

`RespectIgnoreDifferences` requires an existing live object. Forced deletion/recreation
(`Force=true,Replace=true`) can cause an outage or data loss; it is not a generic
triage repair. See [Argo CD 3.4 sync options](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/sync-options/).

## 6. Admission webhooks

The message names the webhook. Find what it is:

```bash
$KCTL get validatingwebhookconfigurations -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
```

A webhook that is *unreachable* rather than *denying* produces a different message —
`failed calling webhook ... connection refused` or `context deadline exceeded` — and is
an infrastructure fault, not a policy rejection. Its `failurePolicy: Fail` turns an
unreachable webhook into a blocked sync for every Application touching that kind.

Correlate failures naming the same webhook across the relevant instance/destination.
Reuse captured errors; if necessary query compact conditions/results in its watched
namespaces. A cluster-wide count of Failed/Error operations mixes historical failures
and unrelated causes, so it does not establish this webhook's blast radius.

## 7. Missing prerequisites

A sync that fails on the first resource of the first wave is usually a missing
prerequisite rather than a bad manifest.

- **Namespace does not exist.** Argo CD does not create it unless
  `CreateNamespace=true` is in `syncOptions`, or the namespace is in the manifests with
  an earlier sync wave.
- **CRD not installed.** Check whether its manifest is in the same sync; Argo CD then
  skips the missing-kind dry run automatically. If another controller supplies the
  CRD, verify that prerequisite and ordering. Skipping dry-run does not install it.
- **Namespace terminating.** Every apply into it fails and nothing is wrong with the
  manifests.

```bash
$KCTL get ns <destination-namespace> -o jsonpath='{.status.phase}{"\n"}'
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='{.spec.syncPolicy.syncOptions}{"\n"}'
```

## 8. Will it retry?

Whether this failure is self-correcting changes the recommendation entirely.

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath=''\
'retry={.spec.syncPolicy.retry}{"\n"}'\
'retryCount={.status.operationState.retryCount}{"\n"}'
```

After a failed operation with no retries remaining, auto-sync does not repeat the
same revision and parameter combination. In Argo CD 3.4 the log is
`Skipping auto-sync: failed previous sync attempt to <last-revisions> and will not retry for <desired-revisions>`;
the condition message starts `Failed last sync attempt to`. The final log argument is
a revision list, not a retry duration. With no `retry` policy, a terminal failure can
therefore leave the app `OutOfSync` after a transient cause clears. A new desired
revision/parameters or a separately authorized manual sync is needed; triage does not
run it. `selfHeal: true` does not retry this failed attempt by itself.

Do not confuse this with `Skipping auto-sync: most recent sync already to <rev>`:
that message follows a **successful** prior sync when self-heal is disabled. Read the
operation phase and actual controller log before choosing between these cases.
Source: [Argo CD 3.4 auto-sync decision](https://github.com/argoproj/argo-cd/blob/release-3.4/controller/appcontroller.go).

## 9. Report

Name the resource, quote the API server or hook message, and say which of sections 3
to 7 it falls into. Then state whether it will retry, because "this cleared an hour ago
and the Application will stay broken until someone syncs it" is usually the most
actionable sentence available.

If the cause is RBAC on an operator-managed instance, do not produce a Role or
RoleBinding manifest. Hand off to `operator-rbac.md`.
