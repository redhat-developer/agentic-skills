# Debugging Report Format

Every debugging session must conclude with a structured report.

## 1. Summary

| Field | Value |
|-------|-------|
| Cluster Context | `<context-name>` |
| Argo Component | Argo CD / Rollouts |
| Component Versions | Operator CSV + Argo CD version, e.g. `openshift-gitops-operator.v1.21.3` / Argo CD v3.4.5 |
| Resource | `<kind>/<namespace>/<name>` |
| Current Status | Sync/Health/Phase status |

**When more than one Argo CD instance is in scope**, repeat sections 1–4 per instance
under an `## Instance: <namespace>` heading, then give one combined section 5. A single
flat report across instances hides which instance owns which fault — and on OpenShift,
`openshift-gitops` plus one or more tenant instances is the normal case, not an edge case.

## 2. Resource Analysis

- **Spec**: key configuration details (source, strategy, template)
- **Status Conditions**: each condition with type, status, message, timestamp
- **Events**: relevant Kubernetes events

## 3. Dependency Chain

Map the full dependency chain relevant to the problem:
- Argo CD: `Git Repo -> Repo Server -> Application -> Managed Resources -> Pods`
- Rollouts: `Rollout -> ReplicaSets -> Pods`, `Rollout -> AnalysisRun -> Metric Provider`

## 4. Root Cause

State the identified root cause with supporting evidence:
- The specific error message or condition
- The resource and field where the failure originates
- The chain of causation from root cause to observed symptom

## 5. Recommendations

Prioritized list of actions:
- **BLOCKER** — must fix to restore functionality
- **HIGH** — significant risk if not addressed
- **MEDIUM** — best practice violation contributing to the issue
- **LOW** — improvement for reliability or observability

**Every recommendation must state its impact, not just its urgency.** Priority says how
soon; impact says what else moves when someone acts on it. A reader deciding whether to
do this now or in a maintenance window needs the second one, and it is the part they
cannot work out from the recommendation itself.

```
BLOCKER — Delete Rollout/openshift-gitops/example (no containers; hot-loops the controller)
  Impact: argo-rollouts controller only. The Rollout is invalid so nothing runs from
          it; no workload is affected. Controller restarts once.

HIGH    — Raise argocd-server memory to 1Gi (OOMKilling at the 256Mi default)
  Impact: restarts argocd-server on the openshift-gitops instance. UI and API
          unavailable for ~30s for everyone using it. Reconciliation is unaffected.
```

Where a cluster and the repository helper are available, compute it rather than guess:

```bash
<repo-root>/scripts/blast-radius.sh <kind> <name> [namespace]
```

It resolves the fan-out for `ArgoCD`, `AppProject`, `ApplicationSet`, `Application`,
`RolloutManager` and the shared ConfigMaps, and is strictly read-only. In a skills-only
bundle the repository helper may be absent; inspect the same ownership and references
with read-only CLI commands. With no cluster, reason it out from the manifests and
**say it was not verified** — an unverified impact
is still far more useful than none.

"Impact: this Application only, nothing else references it" is a good answer. Say it
rather than omitting the line; silence reads as "unknown", which is a different claim.

Three cases worth stating explicitly whenever they apply:
- **Operator-managed objects restart on edit.** The restart is itself the impact and it
  is invisible in a diff.
- **Shared instances.** On OpenShift the default `openshift-gitops` instance is usually
  shared; the person asking typically owns one tenant and is not thinking about the others.
- **Ordering.** If one recommendation must land before another is safe, say so. Enabling
  a gate while a dependency is broken can create the very failure being reported.

---

