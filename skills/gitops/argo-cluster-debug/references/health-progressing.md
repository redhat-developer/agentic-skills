<!-- Loaded on demand by app-health-triage.md when the
     Application health status is Progressing. Read-only. -->

# Progressing

`Progressing` means not healthy yet, but still allowed to become healthy. It is the
normal state during a rollout. The symptom here is that it is *sustained* — it has not
resolved on its own.

## The timing trap

With the built-in check, a failed Deployment rollout can remain `Progressing` until
the observed generation has a `ProgressDeadlineExceeded` condition. The default
`progressDeadlineSeconds` is **600 seconds**, but inspect its actual value and
conditions; paused Deployments and custom assessments differ. A crash-looping
workload and a normal rollout can share this status. Look at the pods.

A long configured deadline delays the timeout; a kind without deadline-based
assessment may remain `Progressing` indefinitely. Neither establishes progress.

## 1. Identify the progressing resource and its message

Use the successful snapshot from `resource-health.md` and select explicit
`Progressing` assessments. Retain the resource identity and health message. If resource
health is unavailable, inspect accessible live conditions and report the evidence gap;
an empty inline field is not an assessment.

The message is diagnostic on its own. Match it before running anything else.

| Message | Meaning |
|---|---|
| `Pending deletion` (possibly with finalizer details) | The object has a `deletionTimestamp`. Go to section 2. |
| `Waiting for rollout to finish: N out of M new replicas have been updated...` | Fewer replicas have been updated than requested; inspect the ReplicaSet and Pods |
| `Waiting for rollout to finish: N old replicas are pending termination...` | Old pods are not going away — inspect rollout constraints, deletion timestamps, finalizers and termination grace periods |
| `Waiting for rollout to finish: N of M updated replicas are available...` | Pods exist but are not ready — readiness probes, section 3 |
| `observed deployment generation less than desired generation` | The controller has not reported observing the current generation. Section 4. |

## 2. Stuck terminating

In 3.4, deletion without a hook finalizer returns `Progressing` / `Pending deletion`
before assessment. Newer builds may assess first: errors can return `Unknown`, and
custom `deletionMessage` can override status/message. Check installed support only
if the observed result differs; otherwise use the 3.4 rule.

```bash
$KCTL get <kind> <name> -n <ns> \
  -o jsonpath='deletionTimestamp={.metadata.deletionTimestamp}{"\n"}finalizers={.metadata.finalizers}{"\n"}'
```

Finalizers can reflect normal cleanup. Correlate deletion age, remaining dependencies
and the owning controller's activity before calling one stuck. Do not strip finalizers
or assume another sync clears the blocker.

A terminating namespace may explain blocked cleanup or creation. Check it once
when relevant; do not assume every remaining object already has a deletion timestamp:

```bash
$KCTL get ns <ns> -o jsonpath='phase={.status.phase}{"\n"}finalizers={.spec.finalizers}{"\n"}'
```

## 3. Pods that will not become ready

`Pending` pods without a qualifying container waiting error are `Progressing`;
inspect scheduling/storage constraints and FailedCreate quota events. A waiting
error with restartPolicy Always can instead produce Degraded (`health-degraded.md`).

```bash
$KCTL get pods -n <ns> -l <selector> \
  -o jsonpath='{range .items[*]}{.metadata.name} {.status.phase} ready={.status.containerStatuses[*].ready} {range .status.conditions[?(@.type=="PodScheduled")]}{.reason}: {.message}{end}{"\n"}{end}'
$KCTL get events -n <ns> --field-selector involvedObject.uid=<pod-or-replicaset-uid> --sort-by=.lastTimestamp | tail -25
```

| What you find | Cause |
|---|---|
| `PodScheduled=False`, reason `Unschedulable` | No node fits — resource requests, taints, node selector, affinity. The event message names which |
| Pending with an unbound PVC | Check the PVC; `WaitForFirstConsumer` deliberately waits for scheduling; inspect the actual scheduling/storage constraint before calling it a deadlock |
| Pending, `exceeded quota` event | ResourceQuota in the namespace |
| Running, `ready=false`, no restarts | Readiness probe failing or still in `initialDelaySeconds` |
| Running, `ready=false`, with restarts | Inspect previous logs using `health-degraded.md`; a Deployment can remain `Progressing` inside its deadline despite crashing child pods |

For a Pod stuck initializing (`Init:...`), inspect `.status.initContainerStatuses`,
not only `.status.containerStatuses`. Read the failing init container's waiting or
termination reason and bounded logs (`-c <init-container>`); application-container
logs may not exist yet. Correlate its dependency, image or configuration error with
Pod events. See [init-container diagnosis](https://kubernetes.io/docs/tasks/debug/debug-application/debug-init-containers/).

A PDB can block API eviction during a node drain; it does not limit a Deployment or
StatefulSet controller's rolling update. Investigate PDBs only with eviction evidence.
Source: [Kubernetes disruptions](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/).

## 4. The controller never acted

`observed deployment generation less than desired generation` means the spec was
written but `status.observedGeneration` has not caught up. The workload controller is
not yet reporting that generation. Check elapsed time, controller activity and
conditions. A rejected admission request does not store the rejected spec; distinguish
a failure creating child resources from a controller that has not observed the update.

## 5. Kinds that sit Progressing by design

Not every sustained `Progressing` is a fault. Confirm which of these you have before
recommending anything:

| Kind | Why |
|---|---|
| Job | With no completion, failure or suspension condition, it is `Progressing`. `Suspended=True` yields `Suspended`. Check logs and progress before calling a long-running job hung |
| Pod with `restartPolicy: OnFailure` or `Never` | Running is normally `Progressing`. On newer builds supporting it, a non-hook Pod with `argocd.argoproj.io/ignore-restart-policy: "true"` instead uses the Always-policy readiness/error checks |
| PVC | Pending is `Progressing`. With `WaitForFirstConsumer` this is correct and resolves when a consumer pod is scheduled |
| Rollout paused at a step | The bundled check maps observed Rollout phase `Paused` to `Suspended`. Investigate another resource, stale status or an override if this does not explain aggregate `Progressing`; `../SKILL.md` has the Rollout workflow |
| Service of type LoadBalancer | Progressing until `status.loadBalancer.ingress` is nonempty; an IP or hostname entry qualifies. Verify provider configuration if it remains empty |

## 6. Decide and report

State which of these you concluded, and the evidence:

- **Wedged.** Something will not complete without intervention — a finalizer, an
  unschedulable pod, a failed webhook, a PDB. Name it.
- **Failing, inside the deadline.** The pods show a real fault and the Deployment has
  simply not hit `ProgressDeadlineExceeded` yet. Diagnose it as the fault it is; it
  may later reach the deadline; waiting for that adds no diagnostic evidence.
- **Still working.** Progress is observable — replica counts moving, job log advancing,
  successive observations of completed work. Report no action required and say what you would expect to
  change next.

A recent `.status.health.lastTransitionTime` is timing evidence, not proof of
progress. Reuse prior observations or collect a bounded follow-up only if needed to
compare ready replicas, completed work or advancing logs.
