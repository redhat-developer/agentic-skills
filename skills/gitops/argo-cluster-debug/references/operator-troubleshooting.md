# Argo CD operator

Load through Workflow 2c in `../SKILL.md`. Reuse the installation and instance evidence
already gathered. File paths below are relative to this reference directory.

Operator-owned behavior for an Argo CD instance installed by the Red Hat OpenShift
GitOps operator. Upstream Argo CD does not create these objects, so the fix is always
an operator input — a label, a CR field, an operator environment variable — never the
reconciled object itself.

This workflow is read-only. Show the operator input that would fix the problem, and stop
there. Desired-state changes belong in Git: hand back the operator input or manifest
to commit and let the responsible controller reconcile it. Do not apply it in diagnosis.

## Unattended diagnosis

When this workflow is used by an automated diagnosis run with no human in the
loop, do not ask questions. Gather the evidence you can
reach, name the most probable cause, and state your confidence and what you could not
check. An honest `Low` confidence diagnosis is useful. A question is not.

Related guidance:

| Need | Reference or action |
|------|-------|
| Operator CRD field reference — RolloutManager, NotificationsConfiguration, NamespaceManagement, ImageUpdater, GitopsService | `../../argo-knowledge/references/openshift-gitops-operator.md` |
| Installing or changing an operator-managed instance | Commit the operator configuration to Git; the OpenShift GitOps Operator reconciles it |
| Sync, health, and controller-log debugging that is not operator-owned | `../SKILL.md` |

## Before any check

Resolve the CLI. On OpenShift, `oc` is the default.

```bash
if command -v oc >/dev/null 2>&1 && oc api-resources --api-group=route.openshift.io 2>/dev/null | grep -q routes; then
  KCTL=oc
elif command -v kubectl >/dev/null 2>&1; then
  KCTL=kubectl
elif command -v oc >/dev/null 2>&1; then
  KCTL=oc
else
  echo "ERROR: no cluster CLI found — install kubectl or oc" >&2; exit 1
fi
```

Confirm the cluster context with `$KCTL config current-context`. Use
`applications.argoproj.io`, never the short name `application`: on Open Cluster
Management clusters the short name is `applications.app.k8s.io` and a miss looks
like the Application does not exist.

Identify the instance before anything else. Most of these topics have a different
answer for a cluster-scoped instance than for a namespace-scoped one:

```bash
NS=<namespace-of-the-ArgoCD-CR>
CR=<name-of-the-ArgoCD-CR>

# Set these two as well whenever the symptom names a specific Application.
APP=<application-name>
APP_NS=<namespace-of-the-application-object>

$KCTL get argocd -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
```

## Route by symptom

Start with the matching topic. These look alike at a distance and have different
fixes. Follow any additional topic implicated by the evidence, retaining completed
checks and outstanding sync or health findings for the final report.

| Symptom | Topic | Reference |
|---|---|---|
| Sync fails `forbidden` or `Unauthorized`; the controller cannot write to the destination namespace | Destination-namespace RBAC | `operator-rbac.md` |
| An `Application` object outside the Argo CD namespace is ignored — no status at all | Apps in any namespace | `operator-apps-in-any-namespace.md` |
| `application '<name>' in namespace '<ns>' is not permitted to use project '<project>'`, or UI access disappeared after enabling `sourceNamespaces` | Apps in any namespace and its AppProject/UI policy layers | `operator-apps-in-any-namespace.md` |

Each is a different permission failure. An empty `.status` is consistent with an
unprocessed Application, while an API authorization denial in a current sync identifies
the controller's Kubernetes rights. Stored status can be stale: use current instance
configuration, reconciliation timestamps and the exact error before choosing a cause.

If the symptom is not operator-owned, hand off rather than guessing. Sync state is
`app-sync-triage.md`, health is `app-health-triage.md`.

## Topic: destination-namespace RBAC

Diagnose whether an instance is allowed to manage resources in an Application's
destination namespace.

### What the operator owns

A namespace-scoped Argo CD instance can deploy only in its own namespace until a
destination namespace is granted to it. The OpenShift GitOps operator creates that
grant. Do not write a Role or RoleBinding for it.

Two paths produce the same objects in the destination namespace:

| Path | Who does it | Operator then creates |
|------|-------------|------------------------|
| Label `argocd.argoproj.io/managed-by: <instance-namespace>` | A cluster admin labels the destination namespace. The value is the namespace the `ArgoCD` CR lives in, not the CR name. | Role and RoleBinding `<argocd-name>-argocd-application-controller` and `<argocd-name>-argocd-server` |
| `NamespaceManagement` | A tenant creates the CR in the destination namespace, after an admin has enabled the feature and the `ArgoCD` CR has opted in. | The same Role and RoleBinding, and the destination namespace is added to the instance cluster secret `<argocd-name>-default-cluster-config` |

The two Roles differ, and neither matches the `admin` ClusterRole. The controller
Role is every verb on every namespaced resource, plus `impersonate` on
ServiceAccounts — broader than `admin`. The server Role is narrower: read, patch, and
delete, with full CRUD on Secrets and ConfigMaps. Neither grants cluster-scoped
resources (Namespace, CRD, ClusterRole). A hand-written binding is not part of this
reconcile and will not be repaired by the operator.

The label works only for namespaces on the same cluster as the operator. A remote
cluster destination needs RBAC created on that cluster. Say so; do not recommend the
label there.

### Labels that are not this grant

| Label or field | What it actually is |
|----------------|---------------------|
| `argocd.argoproj.io/managed-by` | Destination-namespace grant. Value is the Argo CD **namespace**. |
| `argocd.argoproj.io/managed-by-cluster-argocd` | Apps-in-any-namespace. The operator sets it from `sourceNamespaces`. It is where Application objects may live, not permission to deploy workloads. |
| `app.kubernetes.io/managed-by: applicationset-controller` | Marks an Application generated by an ApplicationSet. |
| `argocd.argoproj.io/managed-by-url` | Annotation on an Application that points its UI link at an instance. Not RBAC. |
| AppProject `destinations` | Argo CD policy. Independent of the Kubernetes RoleBinding. Both can fail a sync. |

A namespace should be managed by one instance. If `managed-by` is already set, the
operator will not also create the source-namespace roles for `managed-by-cluster-argocd`.

### Running this topic

Load `operator-rbac.md` and run that workflow in order. Do not
stop at the first missing object. A missing label and an AppProject rejection often sit
on the same Application.

### Scope check comes first

The label and `NamespaceManagement` extend a **namespace-scoped** instance. They are
the wrong fix when:

- The instance is cluster-scoped. Those instances get a ClusterRole and
  ClusterRoleBinding named `<argocd-name>-<argocd-namespace>-argocd-application-controller`
  and `<argocd-name>-<argocd-namespace>-argocd-server`. Which namespaces host a
  cluster-scoped instance is `ARGOCD_CLUSTER_CONFIG_NAMESPACES`, read from the
  operator **Deployment** — the CSV default is `openshift-gitops`, and a Subscription
  entry replaces that default rather than extending it. So the default
  `openshift-gitops` instance is cluster-scoped and is for
  cluster configuration, not application delivery. A forbidden sync there is usually
  the limited default ClusterRole, not a missing label.
- The resource that failed is cluster-scoped. A namespace-scoped instance cannot
  manage it, even with `managed-by` set.
- The destination server is a remote cluster.

### Report

Every destination-namespace RBAC session ends with this report. Quote the field or
object that establishes each claim. A cause with no supporting output fails the
diagnosis.

#### 1. Instance

| Field | Value |
|-------|-------|
| Context | current context |
| ArgoCD | `<namespace>/<name>` |
| Scope | namespace-scoped or cluster-scoped, and the evidence |
| Application | `<namespace>/<name>` |
| Destination | server and namespace from `spec.destination` |

When more than one Argo CD instance exists, repeat the report per instance that could
own the Application. Do not pick one silently.

#### 2. Grant

State which path is in effect, or that neither is:

- Label value on the destination namespace, and whether it equals the instance namespace.
- `NamespaceManagement` in that namespace: `.spec.managedBy`, its
  `.status.conditions`, whether the feature environment is set on the operator
  Deployment, and whether `ArgoCD.spec.namespaceManagement` allows that name. Quote
  the condition, or state that there is none — both are evidence.
- Role and RoleBinding names found or missing.
- `kubectl auth can-i` result for the application-controller ServiceAccount. The
  account is `<argocd-name>-argocd-application-controller` in the **instance**
  namespace. `can-i` against a ServiceAccount that does not exist returns "no" and
  is not evidence that RBAC was denied.

#### 3. Separate checks

AppProject destination and resource restrictions, and whether the failing object is
cluster-scoped. Say explicitly when Kubernetes RBAC is fine and the project is what
rejected the sync, or the reverse.

#### 4. Root cause and recommendation

State one causal chain per independent finding, retaining separate project-policy
and workload faults. If the grant is missing, the recommendation is the label or the
`NamespaceManagement` handshake. It is not a Role or RoleBinding manifest.

State the impact of the recommendation:

- The label gives that instance every verb on every namespaced resource in the
  destination namespace, including `impersonate` on the ServiceAccounts in it. Every
  Application on that instance can deploy there, still subject to the AppProject.
- Do not put the label on a namespace whose `managed-by` value is a different instance.
- `NamespaceManagement` does nothing until the operator environment is true and the
  `ArgoCD` CR allows the namespace. `status.conditions` on the `NamespaceManagement`
  CR distinguishes those two, and an absent condition points at the environment.

## Topic: apps in any namespace

An Application outside the instance's watch scope may remain unprocessed. A newly
created object can have empty status; an older object can retain stale status.

This feature requires a **cluster-scoped instance**. Confirm the instance namespace
against `ARGOCD_CLUSTER_CONFIG_NAMESPACES` in the operator Deployment before judging
missing source-namespace objects. On a supported instance the operator derives the
`argocd.argoproj.io/managed-by-cluster-argocd` label, source-namespace RBAC and workload
arguments from `ArgoCD.spec.sourceNamespaces`. For a namespace-scoped instance, absent
source-namespace RBAC is expected; it does not establish an operator fault. Do not
set generated labels, write generated RBAC, or edit workload arguments manually.

After the scope prerequisite, two layers must agree. Read their current configuration
and correlate it with these symptoms:

| Missing | Symptom |
|---|---|
| The namespace is not in the instance's effective watch configuration | A new Application may have empty status; old status can remain after watching stops |
| The namespace is not in the AppProject's `spec.sourceNamespaces` | `InvalidSpecError` with `application '<name>' in namespace '<ns>' is not permitted to use project '<project>'` |

The AppProject is not operator-generated but can be managed by another Application.
Recommend changes in its authoritative desired state, and name the layer being changed.

Load `operator-apps-in-any-namespace.md`.

## If the run writes a structured result

When the caller supplies an output schema, load `runtime-output.md`. Map this
workflow's findings to that schema; its fields, types and execution contract are
authoritative. Remediation commands, when requested, are proposals for a separate
authorized stage. Diagnosis does not execute them.

## Reference

| Topic | File | When to load |
|-------|------|----------------|
| Destination-namespace RBAC — decision order, commands, and the two grant paths | `operator-rbac.md` | The symptom is a `forbidden` or `Unauthorized` sync, or a question about `managed-by` or `NamespaceManagement` |
| Apps in any namespace — scope prerequisite, watch/project layers and Application addressing | `operator-apps-in-any-namespace.md` | An Application outside the instance namespace is unprocessed, has a project-permission error, or disappeared from the UI |
| Application **sync** state triage | `app-sync-triage.md` | The symptom is `OutOfSync`, a failed or stuck sync, or `Synced` while the cluster is wrong |
| Application **health** status triage | `app-health-triage.md` | The symptom is `Degraded`, `Progressing`, `Missing`, or health `Unknown` |
