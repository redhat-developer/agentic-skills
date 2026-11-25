# Output for a calling runtime

Load only when the caller supplies a structured output schema or requests a structured
remediation plan. This reference adapts findings to that contract; it does not define
a schema, grant execution permissions, or change the selected workflow's write scope.
Triage stays read-only. Explicitly requested Rollout control retains the parent skill's
write protocol, including verification of the resulting phase.

## Follow the supplied contract

Use the caller's exact field names, required fields, types, enums and output envelope.
For example, a boolean `actionRequired` uses `false`, not the string `"False"`.
Use the schema's confidence values rather than assuming capitalization. If it has no
dedicated field for evidence or unavailable checks, preserve them in an allowed
diagnostic text field. Do not invent extra fields or a remediation to fill an optional
section. Validate the result against the supplied schema when a validator is available.

`AnalysisResult` is one possible integration, not a universal contract. Only when the
supplied schema defines them, the following fields can carry the triage findings:

| Finding | Possible AnalysisResult field |
|---|---|
| State, resource, quoted error and causal chain | `diagnosis.summary`, `diagnosis.rootCause` |
| Confidence, qualified by unavailable evidence | `diagnosis.confidence` |
| Whether a change is warranted | `actionRequired` |
| Requested remediation proposal | `remediationPlan.actions[]` |

Do not infer a run's completion state from `actionRequired`, or assume a proposed
RBAC declaration grants access. Lifecycle transitions, approval, permission enforcement
and execution belong to the calling runtime. A schema named `AnalysisResult` alone
does not establish any of those behaviors. With no supplied schema, use the Markdown
report format; in unattended mode report a missing required contract without waiting
for input or fabricating it.

## When remediation proposals are requested

Health triage may establish the cause without an executable fix. Prefer desired-state
corrections in Git. Reuse ownership and effective automation from the parent skill before
proposing a live change (`selfHeal` alone is insufficient): Argo CD or another controller may revert it. If the target
configuration is managed from Git, propose the Git change rather than a temporary patch.
Do not invent an executable command when the target, intended value or ownership is
unresolved; express the limitation using the runtime's supported result fields.

For an operator-managed instance, propose the operator input rather than generated
objects. A separately authorized live-change stage, if appropriate for the ownership
model, would target these inputs:

| Input | Required scope | Avoid |
|---|---|---|
| Namespace `argocd.argoproj.io/managed-by` label | `patch` on cluster-scoped `namespaces` | Hand-written generated Roles or RoleBindings |
| `ArgoCD.spec.sourceNamespaces` on a supported cluster-scoped instance | `patch` on `argocds.argoproj.io` in the instance namespace | Editing generated `--application-namespaces` flags |
| `ArgoCD.spec.rbac.policy` | Same ArgoCD scope | Editing `argocd-rbac-cm` |
| ArgoCD tracking, health or diff settings | Same ArgoCD scope | Editing generated `argocd-cm` |
| AppProject policy | `patch` on `appprojects.argoproj.io` in the project's namespace | Treating project policy as Kubernetes RBAC |

If the contract requires executable commands, resolve target names and values from
evidence rather than returning placeholders. Declare only the permissions those
commands actually require, in the runtime's format, with a justification. The Application
object, instance and workload destination may occupy different namespaces; enumerate
actual targets. Namespace objects themselves require cluster-scoped permissions.
These declarations describe requirements, not permission to act during diagnosis.

Explain impact and reversibility using the supplied risk enums. Enabling prune can
delete managed resources no longer in Git; restoring the setting does not restore
deleted data. An ArgoCD change can affect every Application on the instance and may
restart components. A destination grant permits broad access to namespaced resources,
with effective privileges determined by the installed operator's Role rules or custom
ClusterRole, subject separately to AppProject policy. Do not assume impersonation.

Include verification in the proposed plan: read back the input, check that the operator
reconciled the generated objects, and verify the original symptom. Where supported,
put these in post-check actions. A successful patch response alone does not prove the
fix worked. During read-only triage these remain proposed steps; do not execute the
mutation or claim its post-change checks passed.
