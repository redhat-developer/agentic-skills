# Debugging Report Format

Every debugging session must conclude with a structured report. Keep it concise:
record each observation once and refer to it in the causal explanation, rather than
repeating full snapshots. Include only evidence relevant to the findings.

## 1. Summary

| Field | Value |
|-------|-------|
| Cluster Context | `<context-name>` |
| Argo Component | Argo CD / Rollouts |
| Component Versions | Operator CSV + Argo CD version, e.g. `openshift-gitops-operator.v1.21.3` / Argo CD v3.4.5 |
| Resource | `<kind>/<namespace>/<name>` |
| Current Status | Sync/Health/Phase status |
| Action Required | Whether the evidence warrants a change; do not invent a repair |

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

Give one causal chain per independent finding, with supporting evidence:
- The specific error message or condition
- The resource and field where the failure originates
- The chain of causation from root cause to observed symptom

State confidence explicitly for each cause: **High** for direct verification,
**Medium** for a supported but incomplete chain, **Low** when the underlying cause
cannot be established. A verified rollout timeout can have High confidence while
its underlying pod cause remains Low confidence because pod/log reads were denied.
Name unavailable checks and distinguish them from controller failures.

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

Example: correcting a verified invalid environment value in the Deployment's Git
manifest can replace its pods when reconciled. State the affected workload and any
unverified shared consumers; do not invent restart counts or outage durations.

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
- **Operator-managed changes may roll components.** Establish which workloads the
  particular input affects rather than assuming every edit restarts everything.
- **Shared instances.** On OpenShift the default `openshift-gitops` instance is usually
  shared; the person asking typically owns one tenant and is not thinking about the others.
- **Ordering.** If one recommendation must land before another is safe, say so. Enabling
  a gate while a dependency is broken can create the very failure being reported.

---
