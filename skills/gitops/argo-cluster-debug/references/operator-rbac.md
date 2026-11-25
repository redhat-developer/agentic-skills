<!-- Loaded directly from SKILL.md for destination authorization failures.
     Run the workflow in order. Read-only. Do not create Role or RoleBinding objects. -->

# Destination namespace RBAC

The OpenShift GitOps operator creates the Kubernetes permission that lets an Argo CD
instance manage a destination namespace. The permission is a Role and a RoleBinding in
that namespace. Configure the operator's grant inputs instead of creating parallel
Roles or RoleBindings. Hand-written bindings bypass that lifecycle; the operator may
overwrite objects at its generated names or leave differently named bindings behind.

## Distinguish the permission layers

`managed-by` grants destination workload access; `managed-by-cluster-argocd` is an
operator-generated source-watch label, not this grant. AppProject policy is separate
from Kubernetes RBAC. If the evidence instead concerns ignored Application objects or
source-namespace rejection, read `operator-apps-in-any-namespace.md`.

## Objects the operator creates

In the destination namespace, for Argo CD CR name `<argocd-name>`:

| Name | Kind | Subject |
|------|------|---------|
| `<argocd-name>-argocd-application-controller` | Role and RoleBinding | ServiceAccount `<argocd-name>-argocd-application-controller` in the instance namespace |
| `<argocd-name>-argocd-server` | Role and RoleBinding | ServiceAccount `<argocd-name>-argocd-server` in the instance namespace |

The controller binding is what a sync uses. The server binding is what the UI, API,
and CLI use to read and manage resources in that namespace. Check both. A sync can
fail while the UI still looks healthy, and the reverse.

The two Roles differ. Their rules depend on the distribution, operator version and
custom-role configuration. OpenShift GitOps builds the controller Role from the
cluster's `admin` rules plus product rules; do not assume the upstream wildcard Role
or claim universal ServiceAccount impersonation. Inspect the generated Role and its
binding's `roleRef` before describing the grant. The server has separate rules.
A namespaced RoleBinding grants no cluster-scoped permissions, even when it refers
to a ClusterRole.

If the operator environment sets `CONTROLLER_CLUSTER_ROLE` or `SERVER_CLUSTER_ROLE`
(read them from the operator Deployment, step 1), the operator does **not** create
the default Role. It
creates only a RoleBinding whose `roleRef` is that ClusterRole. The ClusterRole
itself is the administrator's to create. It must allow `get`, `list`, and `watch`,
or the Argo CD CR must limit what the controller touches with `resourceInclusions`
or `resourceExclusions`. A RoleBinding to a ClusterRole that does not exist looks
like "RBAC is missing" and is fixed by creating that ClusterRole, not a second Role.

The cluster secret is `<argocd-name>-default-cluster-config`, and it lives in the
**instance** namespace, not the destination. `NamespaceManagement` adds the
destination namespace to its `namespaces` key, a comma-joined list:

Only inspect that key for a namespace-scoped instance when the handshake needs
confirmation. Preserve read errors before decoding:

```bash
if NS_DATA=$($KCTL get secret "${CR}-default-cluster-config" -n "$NS" -o jsonpath='{.data.namespaces}'); then
  printf '%s' "$NS_DATA" | base64 -d
  printf '\n'
else
  printf '%s\n' 'Namespace secret read failed; retain the error and use accessible grant evidence.' >&2
fi
```

Forbidden leaves this check unverified; NotFound is different evidence. Do not repeat
the read merely to obtain its name or retry an unchanged denial. Accessible RBAC can
also come from a label, so it alone does not prove a NamespaceManagement handshake.

Do not read `<argocd-name>-cluster` for this. That is the admin password secret and
never has a `namespaces` key; finding none there says nothing about the handshake.

The operator does not create `-default-cluster-config` at all for a cluster-scoped
instance, so its absence alongside the default `openshift-gitops` instance is
expected and is not a finding.

Cluster-scoped instances also receive the following cluster-level objects:

| Name | Kind |
|------|------|
| `<argocd-name>-<instance-namespace>-argocd-application-controller` | ClusterRole and ClusterRoleBinding |
| `<argocd-name>-<instance-namespace>-argocd-server` | ClusterRole and ClusterRoleBinding |

Cluster scope does not imply unrestricted workload writes. The default
`openshift-gitops` instance can read broadly while its ClusterRole allows writes to
only selected kinds. A same-cluster destination namespace can still receive the
operator's `managed-by` grant. Inspect both the cluster and namespace permissions;
do not stop this workflow just because a ClusterRole exists. A separate tenant
instance may be an isolation choice, but is not a prerequisite for this grant.

## Workflow

Reuse the identified instance and Application snapshot. If absent, read the
Application's destination/project and operation error together:

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath=''\
'project={.spec.project} destination={.spec.destination}{"\n"}'\
'phase={.status.operationState.phase} message={.status.operationState.message}{"\n"}'\
'{range .status.operationState.syncResult.resources[*]}{.kind}/{.namespace}/{.name} {.status}: {.message}{"\n"}{end}'
```

Set `DEST`, `PROJECT`, `NS` and `CR` from that evidence and verified ownership, not
from the first CR in a listing. `APP_NS` may differ from `NS` under Apps in Any
Namespace. For unresolved ownership use Workflow 1 in `debug-workflows.md`; for a
missing Application use `resource-lookup.md`. Keep candidate instances separate and
initialize every variable needed in each fresh shell. Do not repeat discovery after
ownership is established.

### 1. What is the instance scope and effective permission?

Read the environment from the owning operator **Deployment**, not only the Subscription.
Set `OP_NS`/`OP_DEPLOYMENT` from observed operator ownership (commonly
`openshift-gitops-operator`); resolve referenced configuration if a value uses valueFrom. The
defaults ship in the CSV, and `Subscription.spec.config.env` exists only where an
admin added one. On a default install it is absent, so a Subscription-only read
returns nothing and is not evidence that the variables are unset.

```bash
$KCTL get deploy "$OP_DEPLOYMENT" -n "$OP_NS" \
  -o jsonpath='{range .spec.template.spec.containers[?(@.name=="manager")]}{range .env[?(@.name=="ARGOCD_CLUSTER_CONFIG_NAMESPACES")]}{.name}={.value} from={.valueFrom}{"\n"}{end}{range .env[?(@.name=="ALLOW_NAMESPACE_MANAGEMENT_IN_NAMESPACE_SCOPED_INSTANCES")]}{.name}={.value} from={.valueFrom}{"\n"}{end}{range .env[?(@.name=="CONTROLLER_CLUSTER_ROLE")]}{.name}={.value} from={.valueFrom}{"\n"}{end}{range .env[?(@.name=="SERVER_CLUSTER_ROLE")]}{.name}={.value} from={.valueFrom}{"\n"}{end}{end}'
```

A Subscription entry **replaces** the CSV default rather than adding to it. An admin
who set `ARGOCD_CLUSTER_CONFIG_NAMESPACES=team-a` and dropped `openshift-gitops` made
the default instance namespace-scoped without intending to. The Deployment shows the
merged result; read the Subscription only to attribute a value to someone:

```bash
$KCTL get subscriptions.operators.coreos.com -n openshift-gitops-operator \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.config.env[*]}  {.name}={.value}{"\n"}{end}{end}'
```

Record:

- `ARGOCD_CLUSTER_CONFIG_NAMESPACES` — namespaces whose Argo CD instances are
  cluster-scoped. The CSV default is `openshift-gitops`, which is why that instance
  is cluster-scoped. A first entry of `*` means every namespace. An empty value means
  none, including `openshift-gitops`. Confirm against the ClusterRole below rather
  than the variable alone.
- `ALLOW_NAMESPACE_MANAGEMENT_IN_NAMESPACE_SCOPED_INSTANCES` — must be `"true"` or
  the handshake grants no access and its RBAC may be cleaned up. An independent
  `managed-by` grant can remain; inspect both paths.
- `CONTROLLER_CLUSTER_ROLE` and `SERVER_CLUSTER_ROLE` — when set, expect a
  RoleBinding and no default Role.

```bash
$KCTL get clusterrole "${CR}-${NS}-argocd-application-controller" \
  "${CR}-${NS}-argocd-server"
$KCTL get clusterrolebinding "${CR}-${NS}-argocd-application-controller" \
  "${CR}-${NS}-argocd-server"
```

Correlate those objects with the Deployment environment, binding subjects and actual
rules. Their presence does not prove permission for the verb/kind/namespace in the
error. Continue with destination grants for either scope. Missing or unreadable
cluster RBAC is not evidence that a namespace grant is unnecessary.

### 2. Where is the Application trying to deploy?

Reuse the destination and operation results above; identify the exact controller
identity, denied verb, resource kind and namespace.

Note the verb and kind. If it is cluster-scoped (Namespace, CustomResourceDefinition,
ClusterRole, ClusterRoleBinding, StorageClass), a destination namespace grant cannot
authorize it. Check the instance's cluster-level permissions instead; do not propose
a namespace label as the fix.

Resolve `spec.destination.name` through the registered cluster when used. Establish
whether the destination server is this cluster; a non-default URL needs verification
rather than assuming it is remote. For a confirmed remote cluster, the local `managed-by` label does nothing there.
Inspect the registered remote identity and authoritative remote-cluster permissions;
do not recommend labeling the local namespace.

If `DEST` equals `$NS`, inspect the instance's own reconciled permissions and
AppProject rather than assuming a missing cross-namespace grant. Custom rules can
still deny the operation; verify the exact identity/verb/kind.

### 3. Label path

```bash
$KCTL get ns "$DEST" -o go-template='managed-by={{with .metadata.labels}}{{index . "argocd.argoproj.io/managed-by"}}{{end}}{{"\n"}}source={{with .metadata.labels}}{{index . "argocd.argoproj.io/managed-by-cluster-argocd"}}{{end}}{{"\n"}}deleting={{.metadata.deletionTimestamp}}{{"\n"}}'
# Reuse the known instance inventory; the label selects a namespace, not one CR.
```

Judge the label against these rules:

- The value must equal `$NS`. When the CR name and the namespace differ, a value
  equal to the CR name is wrong.
- Empty or absent, for an instance lacking workload permission in another
  namespace, means this path was not used. Go to step 4 before calling it missing.
- A value equal to some other namespace means a different instance owns the
  namespace. Do not recommend changing it to `$NS`. Say which instance holds it.
- `deletionTimestamp` set: the operator removes `managed-by` from a terminating
  namespace and skips reconcile, which deletes the Role and RoleBinding. The
  missing RBAC is a consequence. Do not recommend putting the label back.
- More than one `ArgoCD` CR in `$NS`: the label names a namespace, not one CR.
  Both instances reconcile their own Role names into `DEST`. Report that; do not
  pretend the label selected one of them.
- `managed-by-cluster-argocd` without `managed-by` is the source-namespace label.
  It does not grant destination admin. Do not treat it as the grant.

### 4. NamespaceManagement path

This is the tenant path. It is off by default. All three of the following have to be
true, and `status.conditions` on the `NamespaceManagement` CR usually tells you which
one is missing — read it before reasoning about the rest:

1. Operator **Deployment** env `ALLOW_NAMESPACE_MANAGEMENT_IN_NAMESPACE_SCOPED_INSTANCES=true`,
   read as in section 1. Do not read the Subscription for this: on a default install
   it carries no `spec.config.env` and an absent entry is not evidence the flag is off.
2. The ArgoCD CR allows the namespace:

```yaml
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: team-argocd
  namespace: team-frontend
spec:
  namespaceManagement:
    - name: payments-*          # both fields required; globs are allowed
      allowManagedBy: true
```

3. The destination namespace contains a `NamespaceManagement` whose
   `spec.managedBy` is exactly `$NS`:

```yaml
apiVersion: argoproj.io/v1beta1
kind: NamespaceManagement
metadata:
  name: managed
  namespace: payments-dev        # the destination namespace
spec:
  managedBy: team-frontend       # the Argo CD instance namespace
```

```bash
$KCTL get argocd "$CR" -n "$NS" -o jsonpath='{.spec.namespaceManagement}{"\n"}'

$KCTL get namespacemanagements.argoproj.io -n "$DEST" \
  -o jsonpath='{range .items[*]}{.metadata.name} managedBy={.spec.managedBy} {.status.conditions}{"\n"}{end}'
```

Read the actual condition message, not just its reason. Newer operators also report
when the feature is disabled; older versions can leave that case without a condition.
Correlate the result with current inputs and the Deployment environment:

| `status.conditions` | What it means |
|---------------------|----------------|
| Absent | Evaluation is unverified. Check the effective feature setting, whether `spec.managedBy` identifies an instance namespace, and reconciliation evidence; absence alone does not establish the cause. |
| `ErrorOccurred`, message says `NamespaceManagement is disabled` | Check the effective feature environment. Do not change the ArgoCD allow-list to fix a disabled feature. |
| `ErrorOccurred`, message says the namespace is not permitted | Inspect all matching `ArgoCD.spec.namespaceManagement` entries. Newer messages distinguish no matching entry from `allowManagedBy: false`; older messages say only that management rules reject the namespace. Establish the missing allow rule from current fields, then recommend that ArgoCD input. |
| `reason: Success` | The operator reported success. Correlate with current inputs, feature enablement and generated bindings/rules; stale success or a custom ClusterRole path does not prove a missing default Role is an outage. |

Quote the condition and its freshness, or its absence. Read the effective environment
instead of inferring enablement solely from absent or historical conditions.

A successful handshake supplies the bindings described above and adds `DEST` to
`$CR-default-cluster-config` in `$NS` for namespace-scoped instances; cluster-scoped
instances do not use that namespace list. Changing or deleting the handshake, or
disabling the feature, can remove its grant and cluster-secret entry. Newer operators
preserve a same-instance `managed-by` grant during this cleanup. Reuse the label and
binding evidence: remaining RBAC can be expected, and a vanished grant requires
checking effective configuration rather than assuming the Application was deleted.

`spec.managedBy` is the only field on `NamespaceManagement`, and it is required.
Each `ArgoCD.spec.namespaceManagement` entry requires both `name` and
`allowManagedBy`.

### 5. Did the operator actually create the RBAC?

```bash
$KCTL get rolebinding "${CR}-argocd-application-controller" "${CR}-argocd-server" -n "$DEST" \
  -o jsonpath='{range .items[*]}{.metadata.name} roleRef={.roleRef.kind}/{.roleRef.name} subjects={.subjects}{"\n"}{end}'
```

Read the referenced Role or custom ClusterRole's `.rules` only when not already
captured. Check both subjects and effective permissions for the denied verb/kind;
object existence alone is insufficient. Do not request default Roles when configured
ClusterRole bindings intentionally replace them.

Read the result as follows:

| What you see | What it means |
|--------------|----------------|
| Both Roles and both RoleBindings exist, subjects point at `$NS` | The grant objects exist. Verify their rules for the denied action, then check the project. |
| RoleBindings exist, Roles do not, and `CONTROLLER_CLUSTER_ROLE` or `SERVER_CLUSTER_ROLE` is set | Expected shape. Check that the named ClusterRole exists and can `get`/`list`/`watch`. |
| Label or a completed handshake is present, and these objects are absent | Reconciliation is a candidate after scope, current inputs and expected object shape are verified. Check operator health in step 7. Do not create the Role. |
| A RoleBinding with a different name exists | Inspect its owner and rules; the name alone does not establish who created it. Do not extend unrelated RBAC or replace operator-owned inputs with a manual grant. |
| Label value is wrong or points at another instance | Fixing names here will not help. The label decides which instance reconciles. |

Also confirm the ServiceAccount exists before trusting `auth can-i`:

```bash
$KCTL get sa "${CR}-argocd-application-controller" -n "$NS"
$KCTL auth can-i create deployment \
  --as="system:serviceaccount:${NS}:${CR}-argocd-application-controller" \
  -n "$DEST"
```

Use the exact verb and kind from the error instead of `create deployment`. A forbidden
impersonation/SelfSubjectAccessReview request is a diagnostic evidence gap, not a
controller permission result. `no` with the SA present
and the RoleBinding present means the rules do not allow that kind. `no` with the SA
absent means the account name is wrong or the instance is not installed. Say which
one you observed.

### 6. Independent AppProject restrictions

Kubernetes RBAC and the AppProject both have to allow the destination. Check the
project even when the Role is missing, so the report does not hide a second cause.

```bash
# PROJECT comes from the current Application snapshot.
$KCTL get appprojects.argoproj.io "$PROJECT" -n "$NS" \
  -o jsonpath='destinations={.spec.destinations}{"\n"}namespaceAllow={.spec.namespaceResourceWhitelist} namespaceDeny={.spec.namespaceResourceBlacklist}{"\n"}clusterAllow={.spec.clusterResourceWhitelist} clusterDeny={.spec.clusterResourceBlacklist}{"\n"}'
```

The initial `default` project is permissive, but administrators can restrict it. Read
its actual policy just as for a team project. A missing allowed destination or a
resource allow/deny restriction can reject the sync independently of Kubernetes RBAC. Quote the project field. Recommend a project change only when that field
is what excludes the destination. Do not recommend the `default` project as the fix.

### 7. Operator health, when the spec is right and the objects are absent

First establish which grant objects should exist. A custom ClusterRole path has no
default namespace Role by design. Only missing expected bindings/rules after valid
current inputs justify investigating reconciliation; reapplying a correct label is
not evidence-based remediation.

```bash
$KCTL get pods -n openshift-gitops-operator
$KCTL get csv -n openshift-gitops-operator \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase
$KCTL get argocd "$CR" -n "$NS" -o jsonpath='phase={.status.phase}{"\n"}'
```

Correlate current operator readiness, relevant CSV/InstallPlan conditions and recent
reconciliation errors with this instance. A replacing CSV or historical pod failure
alone does not prove the blocker. Workflow 6 in `debug-workflows.md` covers that
follow-up when the evidence points to OLM or conversion.

Also reuse the namespace observation from step 3: a terminating destination namespace is the operator behaving
correctly, not a stuck reconcile.

## What to recommend

Recommend one of these, and only when the workflow showed it is the missing piece.

Label, applied by a cluster admin to the destination namespace:

```bash
oc label ns <destination> argocd.argoproj.io/managed-by=<instance-namespace>
```

Or the `NamespaceManagement` handshake in step 4, when the tenant should not need
cluster-admin and the Subscription env is already true or the user is willing to
have an admin set it.

Say the impact with the recommendation. The grant gives the instance broad access
in that destination namespace, available to Applications on the instance subject
separately to AppProject policy. Describe the effective Role rules or custom
ClusterRole, not an assumed wildcard grant. It does not extend to cluster-scoped
kinds or to a remote cluster.

Do not recommend:

- A Role or RoleBinding manifest for the application-controller ServiceAccount.
- `managed-by-cluster-argocd` as a substitute for `managed-by`.
- Adding the label on a namespace that already names a different instance.
- Using this grant so a namespace-scoped instance can create Namespaces or CRDs.

## Source and version check

Verify the installed operator release, CRD schema and effective Role/ClusterRole rules
before recommending grants. Behavior in one source version does not guarantee support
in every packaged release. Relevant GitOps Operator code is `setManagedNamespaces`
in `argocd-operator/controllers/argocd/util.go`, reconciliation in `rolebinding.go`,
and the OpenShift Role hook in `controllers/argocd/openshift/openshift.go`.
