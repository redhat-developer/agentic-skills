<!-- Loaded on demand by app-health-triage.md when the
     Application health status is Degraded. Read-only. -->

# Degraded

A health check ran and reported failure. Something is wrong now, as opposed to not
finished yet. A `Degraded` Application may also contain absent resources: in Argo CD
3.4 individual missing resources do not lower aggregate health. Check both the live
health failure and independent missing-resource sync findings.

`Degraded` with sync status `Synced` means the live state matches git. Drift is not the
cause and syncing again changes nothing. Say that explicitly when you see it; it is the
most common wrong recommendation for this status.

## 1. Find the resource that produced the status

Use the successful snapshot from `resource-health.md` and select explicit
`Degraded` assessments. Retain the resource identity and health message. If resource
health is unavailable, inspect accessible live conditions and report the evidence gap;
an empty inline field is not an assessment.

The health message is the check's own words. Quote it in the report — it usually names
the cause, and inventing a different one when the message disagrees is a failed
diagnosis.

Correlate owner references and failure evidence before combining degraded resources
into one causal chain. A Deployment, its ReplicaSet, and its Pods all going `Degraded`
together is one fault, not three.

## 2. Match the message to the check that produced it

### Deployment: `exceeded its progress deadline`

The Deployment's `Progressing` condition reached `ProgressDeadlineExceeded`. This is a
timeout, not a diagnosis — it says the rollout did not finish within
`progressDeadlineSeconds` (default 600). The real cause is in the pods.

```bash
$KCTL get deploy <name> -n <ns> \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
$KCTL get pods -n <ns> -l <selector> \
  -o jsonpath='{range .items[*]}{.metadata.name} {.status.phase} {range .status.containerStatuses[*]}{.state.waiting.reason}{" "}{.lastState.terminated.reason}{end}{"\n"}{end}'
```

Do not stop at the deadline message. Report what the pods are doing.

### Pod-backed Degraded

A Pod is `Degraded` in exactly these cases:

| Condition | Note |
|---|---|
| A container is waiting with a reason starting `Err`, or ending `Error` or `BackOff` | `CrashLoopBackOff`, `ImagePullBackOff`, `ErrImagePull`, `CreateContainerConfigError`, `InvalidImageName`. **Only when `restartPolicy: Always`.** |
| Pod phase `Failed` | Message is the pod message, else a container's termination message, else `OOMKilled`, else the non-zero exit code |
| Pod phase `Running`, not ready, and some container has a previous termination | A restart loop that has not yet reached backoff |

Two exclusions that change the diagnosis:

- **`Pending` without a qualifying container waiting error is `Progressing`.** An unschedulable pod, one blocked on
  an unbound PVC, or one waiting on quota does not produce `Degraded`. This is the Pod assessment; a Deployment can become `Degraded` after its deadline
  because its child pods remain Pending. Check which resource produced the status.
- **Pods with `restartPolicy: OnFailure` or `Never` never take the waiting-reason
  path.** This is deliberate, so a hook pod with `ImagePullBackOff` does not fail its
  sync prematurely. A Job's pod in `ImagePullBackOff` leaves the Job `Progressing`.

Get the evidence directly:

```bash
$KCTL get pod <pod> -n <ns> \
  -o jsonpath='phase={.status.phase}{"\n"}restartPolicy={.spec.restartPolicy}{"\n"}{range .status.containerStatuses[*]}{.name} ready={.ready} restarts={.restartCount} waiting={.state.waiting.reason} lastTerm={.lastState.terminated.reason}:{.lastState.terminated.exitCode}{"\n"}{end}'
$KCTL logs <pod> -n <ns> -c <failing-container> --previous --tail=50
$KCTL get events -n <ns> --field-selector involvedObject.name=<pod> \
  --sort-by=.lastTimestamp | tail -20
```

`--previous` often captures the crash before restart. Request it only when a previous
container exists; use bounded current logs when they contain the needed evidence.

Common causes and the evidence that confirms each:

| Cause | Confirmed by |
|---|---|
| Bad image or tag | `ErrImagePull` / `InvalidImageName`, event text naming the registry |
| Registry auth or rate limit | `ImagePullBackOff` with `401`, `403`, or `toomanyrequests` in the event |
| Application crash on startup | `CrashLoopBackOff`, non-zero exit code, stack trace in `logs --previous` |
| OOM | `lastState.terminated.reason: OOMKilled`; compare to `resources.limits.memory` |
| Missing ConfigMap or Secret | `CreateContainerConfigError`, event naming the object. Note the object being missing does **not** itself make the app `Missing` |
| Failing readiness probe | Running, `ready=false`, no termination; probe failure events |

### Job: `Degraded`

The Job has a `Failed` condition; the message is that condition's message. Inspect the
pods it created, with `--previous` as above. A Job that is merely incomplete is
`Progressing`, not `Degraded`.

### A custom Lua script returned Degraded

If the kind is a CRD, or the message does not look like any built-in check, the status
may come from `resource.customizations.health.<group>_<Kind>` in `argocd-cm`:

```bash
# Example grouped kind; use the actual implicated key.
$KCTL get cm argocd-cm -n "$NS" -o jsonpath='{.data.resource\.customizations\.health\.example\.com_Widget}{"\n"}'
```

For core kinds use a kind-only key, such as `resource.customizations.health.Pod`.
If no split key exists, inspect the relevant entry in legacy `resource.customizations`
or the bundled check. Then compare the script against the resource evidence. Read the CR's own
status and compare. A script asserting `Degraded` on a CR that looks healthy is a bug
in the script. On an operator-managed instance, propose the override in the
`ArgoCD` CR's `resourceHealthChecks`; a direct `argocd-cm` edit is reconciled away.

## 3. Check what the status is hiding

Review the complete successful snapshot from `resource-health.md` for explicit
unhealthy assessments and missing-resource sync findings. Inspect absent live objects
through `health-missing.md`. Do not use a negative text filter such as `grep -v Healthy`:
a row without health would falsely look unhealthy.

Report independent problems as additional findings. If tree access was unavailable,
state that secondary health findings could not be fully checked instead of reporting
that none exist.

## 4. Before suggesting anything

Reuse effective automation from the Application snapshot (`../SKILL.md`). Self-heal
can revert relevant live drift only when automation is enabled; `selfHeal: true` with
`automated.enabled: false` does not establish reversion. Regardless of automation,
manifest defects such as a bad image, limit or environment value belong in Git.
Report the exact observed defect and durable correction; do not execute a live edit.
