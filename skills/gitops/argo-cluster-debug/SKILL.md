---
name: argo-cluster-debug
description: >
  Debug and troubleshoot Red Hat OpenShift GitOps on live clusters — inspects Argo CD
  Application sync status, health checks, and controller logs; diagnoses Argo Rollouts
  canary/blue-green failures and AnalysisRun results; and handles multi-instance,
  operator-managed installs. Prefers argocd/oc CLIs when available, falls back to kubectl
  for CRD inspection. Argo Workflows and Argo Events are out of scope. Use when users
  report failing, stuck, or degraded Argo CD or Rollouts resources on a cluster.
license: MIT
compatibility: Requires oc or kubectl; optionally argocd and kubectl-argo-rollouts
---

# Argo Cluster Debug

Diagnose Argo CD and Argo Rollouts using read-only evidence. Paths below are relative
to this skill; paths inside references are relative to the containing document.

## Read before diagnosing

Read the reference matching the observed symptom before selecting specialized checks
or recommending a fix. Use the available file-reading tool to read its contents;
selecting or naming a path does not count as reading it. Resolve paths from the
loaded skill location, including in Lightspeed bundles. Load only relevant guides and reuse references already
successfully read in this run. If a required file is missing, unreadable or truncated,
report the limitation, continue accessible evidence checks, and do not invent its
procedure. Read an unread remainder when available; do not restart completed reads.

## Debugging Workflows

Known symptoms go directly to their procedure. Use the health/sync overviews only for
unresolved status selection or aggregation questions.

| Workflow / signal | Required reference |
|---|---|
| 2c: Operator-managed controller cannot create/update a destination resource (`forbidden`, API authorization denial) | `references/operator-rbac.md` |
| 2c: Ignored Application, empty/stale status outside watch scope, source-namespace project rejection, UI access after a move | `references/operator-apps-in-any-namespace.md` |
| 2b: `ComparisonError`, `InvalidSpecError`, sync `Unknown`, repo auth/render error | `references/sync-comparison-error.md` |
| 2b: Operation stuck `Running` / `Terminating` | `references/sync-stuck.md` |
| 2b: Operation `Failed` / `Error`, without a more specific operator cause above | `references/sync-failed.md` |
| 2b: `OutOfSync`, no operation running or comparison error | `references/sync-outofsync.md` |
| 2b: `Synced` but unexpected live state | `references/sync-false-synced.md` |
| 2a: Health `Degraded` | `references/health-degraded.md` |
| 2a: Sustained health `Progressing` | `references/health-progressing.md` |
| 2a: Health `Missing` | `references/health-missing.md` |
| 2a: Health `Unknown` (not sync `Unknown`) | `references/health-unknown.md` |
| 2a/2b: Status/phase not yet known, or aggregate health semantics needed | `references/app-health-triage.md` or `references/app-sync-triage.md`, according to the question |
| 1: Installation discovery or suspected component failure; 2: other Application questions; 3: ApplicationSet; 4: Rollout; 5: component logs; 6: operator/OLM reconciliation | Matching workflow in `references/debug-workflows.md` |

Start with the current causal error: a controller authorization denial can explain
both `OutOfSync` and `Missing`, while Git HTTP 401 belongs to comparison triage.
Read both relevant procedures for independent health and sync/operator faults.
`Synced` + `Degraded` is a health failure; `OutOfSync` + `Degraded` may need both
branches. Stop a branch once its cause is verified; continue outstanding independent
findings. Do not follow it with a generic survey.

Before filtering resource health, read `references/resource-health.md` unless a
successful current-run snapshot already establishes those assessments. Empty inline
health is not a verdict: 3.x can store it externally. `Progressing` does not establish
progress, even inside a Deployment's deadline; inspect the workload evidence.

## Evidence and execution

1. Establish the requested/current cluster context, resource identity and owning
   instance. Use `oc` on known OpenShift installations when available; otherwise use
   `kubectl` or `oc`. Argo CD and Rollouts CLIs are optional. A denied discovery read
   does not establish platform or installation type. Prefer explicit context options
   when targeting a different cluster; align any Argo CD CLI session with that target.
2. Use `applications.argoproj.io`, not ambiguous short names. `APP_NS` is the
   Application object's namespace, `NS` the instance namespace, and `DEST` the workload
   destination. For an empty/NotFound lookup read `references/resource-lookup.md`.
   Never select the first ArgoCD CR or silently substitute an instance. If ownership
   is unresolved, use Workflow 1 in `references/debug-workflows.md` for discovery.
3. Reuse current-run identity, installation and Application evidence. Do not require
   a full installation survey for a workload error. Expand to Workflow 1 only for
   unresolved installation questions or evidence of a component problem.
4. Fetch related fields together with JSONPath or filtered JSON: identity, project,
   destination, source/revisions, sync policy, conditions, sync/health and operation
   state as needed. Keep comparison status, operation result and health distinct.
   Preserve source indexes and revision arrays for multi-source Applications.
5. Reference commands are evidence requests, not a checklist to repeat. Reuse a
   successful observation of the same object/context; retain its timestamp and
   provenance. Refresh only to resolve changed state, stale evidence or a progress
   question. Read only missing fields at a handoff.
6. Avoid full YAML, annotations, managedFields and unrelated configuration by default.
   Select the fields that test the hypothesis. Scope events to resource UID/name and
   logs to the observed pod/container, time window and bounded tail. Expand a truncated
   result when needed to establish the cause; never treat omitted evidence as absent.
   Redact credentials in URLs, condition messages and logs before reporting them.
7. A denied read is unavailable evidence, not proof of absence or controller RBAC
   failure. Do not retry unchanged failures or seek extra privileges in diagnosis.
   Change the approach or report the gap. In unattended runs, report ambiguity and
   confidence without questions; investigate candidate instances separately.
8. Shell calls may start fresh. Initialize every variable used (`KCTL`, `NS`, `CR`,
   `APP`, `APP_NS`, and any workload/pod variables) in each call, or combine related
   commands in one call. Use observed names/selectors; examples using `$CR` component
   names must be adapted to the actual deployment, including standalone installs.

For inconclusive component checks use `references/troubleshooting.md`, reading only
the relevant section. A specialized procedure that establishes a cause needs no
additional generic troubleshooting.

## Operator and desired-state safety

- Destination workload permissions use `argocd.argoproj.io/managed-by` with the
  **instance namespace** as value, or the supported `NamespaceManagement` handshake.
  Do not recommend hand-written operator-owned Roles/RoleBindings. Cluster scope
  alone does not establish permission to create every workload kind.
- Watching Applications elsewhere uses `ArgoCD.spec.sourceNamespaces` on a supported
  cluster-scoped instance, plus AppProject `spec.sourceNamespaces`. Destination grants
  do not enable watching. Do not edit generated labels, flags or ConfigMaps.
- Distinguish controller authorization, diagnostic-reader denial, repository
  authentication and admission rejection; they have different owners and fixes.
- Recommend authoritative Git or ArgoCD CR changes. Read the effective automation
  policy before predicting reversion: absent `automated` or `automated.enabled: false`
  disables auto-sync; `{}` or omitted/null `enabled` enables it. `selfHeal: true` alone
  does not prove a live change will be reverted. Do not enable automation as a generic
  fix for an intentionally manual-sync Application.
- Inspect the installed CRD schema/version before recommending operator fields.
  Source checks against an operator commit do not prove every packaged release
  supports the same inputs. Credential rotation belongs to its authoritative secret
  management: see `../argo-knowledge/references/openshift-gitops-operator.md` when needed.

## Writes: Rollout control only

Diagnosis is read-only: do not sync Applications, refresh by mutation, edit resources,
install components, or delete Applications. Only explicitly requested Argo Rollouts
runtime control — **promote, abort, retry** — is in scope for writes.

Each permitted write follows [`../write-safety.md`](../write-safety.md): Generate →
Preview → Blast radius → Confirm → Verify. Destructive operations additionally require
the resource name as confirmation. If the target is ambiguous, resolve it before a
write. Verify resulting Rollout phase, abort flag, step and conditions, not just CLI
exit status. A proposed command does not authorize execution.

## Report

Use `references/report-format.md` for Markdown, or `references/runtime-output.md`
when the caller supplies a schema; obey its fields and types. Give one evidence-backed
causal chain per independent finding, confidence, unavailable checks, whether action
is required, and recommendation impact. Separate instances and distinguish verified
causes from reported/unverified symptoms. Do not invent remediation for intentional
suspension or other working-as-configured states; continue independently observed
faults even when the aggregate status appears healthy.

## Edge cases

- Missing namespace or denied CRD discovery alone does not prove Argo CD is absent.
- If an optional CLI is unavailable or unauthenticated, use Kubernetes evidence and
  state which diff/history could not be obtained. Inspect error output as well as exit
  status; do not repeatedly retry a broken Argo CD core-mode connection.
- Without traffic management, Rollouts canary weights approximate replica ratios.
- Multi-source entries can fail independently. Helm values paths can be chart-relative
  or reference another source through `$ref`; follow `references/sync-comparison-error.md`.
- Argo CD/Rollouts CRs use `argoproj.io/v1alpha1`; operator ArgoCD CRs commonly use
  `argoproj.io/v1beta1`. Discover the served schema rather than assuming it.
