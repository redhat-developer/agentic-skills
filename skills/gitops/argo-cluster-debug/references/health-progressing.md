<!-- Loaded on demand by app-health-triage.md when the
     Application health status is Progressing. Read-only. -->

# Progressing

`Progressing` means not healthy yet, but still allowed to become healthy. It is the
normal state during a rollout. The symptom here is that it is *sustained* — it has not
resolved on its own.

The judgment this file exists to support is: **wedged, or still working?** Both look
identical in the Application status. Getting it wrong in either direction is costly —
recommending action on a healthy rollout, or reporting "still progressing" about
something that will never finish.

## The timing trap

A failing Deployment reports `Progressing`, not `Degraded`, until its `Progressing`
condition reaches `ProgressDeadlineExceeded`. `progressDeadlineSeconds` defaults to
**600 seconds**. Any automated trigger with a grace period shorter than ten minutes
sees failing Deployments as `Progressing`.

So for the first ten minutes, a Deployment whose pods are in `CrashLoopBackOff` and a
Deployment that is rolling out normally are the same status. Never infer "it is still
working" from `Progressing`. Look at the pods.

If `progressDeadlineSeconds` is set very high, or the workload is a kind with no
deadline concept, the Application can sit `Progressing` indefinitely and will never
reach `Degraded` on its own.

## 1. Identify the progressing resource and its message

Use the successful snapshot from `resource-health.md` and select explicit
`Progressing` assessments. Retain the resource identity and health message. If resource
health is unavailable, inspect accessible live conditions and report the evidence gap;
an empty inline field is not an assessment.

The message is diagnostic on its own. Match it before running anything else.

| Message | Meaning |
|---|---|
| `Pending deletion` | The object has a `deletionTimestamp`. Go to section 2 — this is the most common sustained case and has nothing to do with the rollout. |
| `Waiting for rollout to finish: N out of M new replicas have been updated...` | New pods have not been created yet |
| `Waiting for rollout to finish: N old replicas are pending termination...` | Old pods are not going away — inspect rollout constraints, deletion timestamps, finalizers and termination grace periods |
| `Waiting for rollout to finish: N of M updated replicas are available...` | Pods exist but are not ready — readiness probes, section 3 |
| `observed deployment generation less than desired generation` | The Deployment controller has not acted on the spec at all. Section 4. |

## 2. Stuck terminating

A resource with a `deletionTimestamp` and no hook finalizer is `Progressing` with
message `Pending deletion`, regardless of anything else. A finalizer that never
completes holds this forever.

```bash
$KCTL get <kind> <name> -n <ns> \
  -o jsonpath='deletionTimestamp={.metadata.deletionTimestamp}{"\n"}finalizers={.metadata.finalizers}{"\n"}'
```

Finalizers can reflect normal cleanup. Correlate deletion age, remaining dependencies
and the owning controller's activity before calling one stuck. Do not strip finalizers
or assume another sync clears the blocker.

A namespace stuck `Terminating` produces the same shape across every resource in it,
and is worth checking once before diagnosing resources individually:

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
| Job | A Job with no `Complete` or `Failed` condition is `Progressing`. A legitimately long job looks identical to a hung one — check the pod's logs and age, not just the Job |
| Pod with `restartPolicy: OnFailure` or `Never` | Running is `Progressing`, not `Healthy`, because these pods are expected to terminate. Hook pods and Job pods are in this class |
| PVC | Pending is `Progressing`. With `WaitForFirstConsumer` this is correct and resolves when a consumer pod is scheduled |
| Rollout paused at a step | An Argo Rollouts canary awaiting promotion is working as configured. `../SKILL.md` has the Rollout workflow |
| Service of type LoadBalancer | Progressing until an ingress IP is assigned; on a cluster with no load balancer provider this never completes |

For these, the correct output is frequently a diagnosis with **no action required**.
Saying "this Job has been running 14 minutes and is still making progress, no action
needed" is a complete and correct answer.

## 6. Decide and report

State which of these you concluded, and the evidence:

- **Wedged.** Something will not complete without intervention — a finalizer, an
  unschedulable pod, a failed webhook, a PDB. Name it.
- **Failing, inside the deadline.** The pods show a real fault and the Deployment has
  simply not hit `ProgressDeadlineExceeded` yet. Diagnose it as the fault it is; it
  will become `Degraded` on its own, and waiting for that adds nothing.
- **Still working.** Progress is observable — replica counts moving, job log advancing,
  successive observations of completed work. Report no action required and say what you would expect to
  change next.

A recent `.status.health.lastTransitionTime` is timing evidence, not proof of
progress. Reuse prior observations or collect a bounded follow-up only if needed to
compare ready replicas, completed work or advancing logs.
