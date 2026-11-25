<!-- Loaded directly from SKILL.md when an Application
     object outside the Argo CD namespace is ignored. Read-only. Do not create Role or
     RoleBinding objects. -->

# Apps in any namespace

By default an Argo CD instance only reads `Application` objects in its own namespace.
A newly created Application outside its watch scope may have no status at all.
An older Application can retain stale status after that scope changes, so check
`reconciledAt`, current configuration and controller evidence before deciding it is
still watched.

Letting Applications live elsewhere is the `sourceNamespaces` feature. The operator
generates its labels, RBAC and workload arguments from the CR, but this feature
requires a cluster-scoped instance. Establish that prerequisite before diagnosing
missing generated objects. Do not create the label, flags or RoleBindings by hand.

## This is not the `managed-by` grant

The two are routinely confused because both involve a namespace and both produce RBAC.
They answer different questions. A source-namespace watch does not itself establish
permission to deploy; inspect destination authorization separately for the instance's
scope:

| | `sourceNamespaces` | `argocd.argoproj.io/managed-by` |
|---|---|---|
| Question | Where may `Application` **objects** live? | Where may **workloads** be deployed? |
| Set by | `.spec.sourceNamespaces` on the `ArgoCD` CR | A label on the destination namespace |
| Operator then | Configures watching and reconciles source-access RBAC/labels, subject to the existing namespace grants and ownership in step 2 | Creates the destination Role and RoleBinding for the controller and server |
| Symptom when missing | The Application is ignored entirely — no status, not in the UI | The Application syncs and fails `forbidden` |

If the Application has no current reconciliation evidence, investigate its watch
scope here. If a current sync is `forbidden`, continue with `operator-rbac.md`.

## 0. Confirm the instance supports this feature

Reuse established scope and instance evidence. Otherwise identify the owning operator
Deployment (`OP_DEPLOYMENT`, `OP_NS`) and read `ARGOCD_CLUSTER_CONFIG_NAMESPACES` from its effective
environment, not just an optional Subscription override:

```bash
$KCTL get deploy "$OP_DEPLOYMENT" -n "$OP_NS" \
  -o jsonpath='{range .spec.template.spec.containers[?(@.name=="manager")].env[?(@.name=="ARGOCD_CLUSTER_CONFIG_NAMESPACES")]}{.name}={.value} from={.valueFrom}{"\n"}{end}'
$KCTL get clusterrole "${CR}-${NS}-argocd-application-controller" \
  "${CR}-${NS}-argocd-server"
```

The instance namespace must be in the configured cluster-scoped set. Confirm the
scope against the generated ClusterRoles; if the environment or roles cannot be read,
report scope as unverified rather than assuming the default. The operator's
[`reconcileRoleForApplicationSourceNamespaces`](https://github.com/argoproj-labs/argocd-operator/blob/v0.18.0/controllers/argocd/role.go#L203)
returns without generating source-namespace Roles for a namespace-scoped instance.
Missing source-namespace objects are therefore expected in that configuration,
even when `spec.sourceNamespaces` is stored in the CR. Report the unsupported scope;
do not diagnose an operator outage or recommend manually creating those objects.
Moving to a supported instance or changing instance scope is an administrative
design decision with broader access implications, not a triage action.

## 1. Confirm the Application is being ignored

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath=''\
'sync={.status.sync.status}{"\n"}'\
'health={.status.health.status}{"\n"}'\
'reconciledAt={.status.reconciledAt}{"\n"}'\
'conditions={.status.conditions}{"\n"}'
```

An empty `.status` is consistent with an Application that has never been processed.
It is not proof of the cause: verify the instance's supported scope and actual
namespace configuration. A populated but old status likewise does not prove the
instance is watching the Application now.

Distinguish from the near-identical case where the instance *is* watching the namespace
but the AppProject refuses the Application: that produces a status with an
`InvalidSpecError` condition with the message
`application '<name>' in namespace '<ns>' is not permitted to use project '<project>'`.
Section 3 covers that separate policy gate.

## 2. Is the namespace in `sourceNamespaces`?

```bash
$KCTL get argocd "$CR" -n "$NS" -o jsonpath='{.spec.sourceNamespaces}{"\n"}'
```

Glob patterns are allowed, so `team-*` covers `team-frontend`. Matching is against the
namespace the **Application object** lives in, not the destination namespace.

For a confirmed cluster-scoped instance, verify the operator acted on the retained
field. Reuse namespace and binding evidence already collected; otherwise read both
ownership labels and the binding targets together:

```bash
$KCTL get ns "$APP_NS" \
  -o go-template='{{range $key, $value := .metadata.labels}}{{if or (eq $key "argocd.argoproj.io/managed-by") (eq $key "argocd.argoproj.io/managed-by-cluster-argocd")}}{{printf "%s=%q\n" $key $value}}{{end}}{{end}}deleting={{.metadata.deletionTimestamp}}{{"\n"}}'

$KCTL get rolebindings -n "$APP_NS" \
  -o jsonpath='{range .items[*]}{.metadata.name} roleRef={.roleRef.kind}/{.roleRef.name} subjects={.subjects}{"\n"}{end}'
```

Only present labels are printed; `=""` means a present but empty value. Both labels
name an Argo CD **namespace**, not a CR name. Interpret the generated state before
diagnosing a missing grant:

- The inspected Red Hat GitOps Operator skips source namespaces with a
  `deletionTimestamp`; the inspected upstream operator code lacks that guard.
  Check installed behavior before attributing missing objects to reconciliation failure.

- A nonempty `managed-by` label makes the operator skip separate source-access
  Roles/RoleBindings. When it names this instance namespace, its destination grant
  can already supply access to Application objects. A matching source label and its
  separate objects may be cleaned up; their absence alone is not a fault.
- If `managed-by` names another instance namespace, or the source label is present
  with any value different from this instance namespace (including empty), source-object
  generation is deliberately skipped. Report the conflicting or invalid owner;
  do not overwrite either label or manufacture bindings.
- Without those skip conditions, the operator normally generates the
  `managed-by-cluster-argocd` label and source-access binding. The label is derived
  from `sourceNamespaces`, not an input to set by hand.

For bindings belonging to the intended instance, verify the subjects and referenced
Role/ClusterRole rules for the needed Application access; reuse known cluster-level
permissions. A label alone does not prove effective access. The watch configuration
and AppProject gate remain necessary even when existing grants supply the RBAC.

Use the discovered workload names/kinds and resolve referenced configuration when
needed. Confirm the flag reached the workloads. The operator renders `sourceNamespaces` into
the controller and server arguments, and a CR that was edited but never reconciled is
visible here:

```bash
$KCTL get statefulset "$CR"-application-controller -n "$NS" \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name} command={.command} args={.args}{"\n"}{end}'
$KCTL get deploy "$CR"-server -n "$NS" \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name} command={.command} args={.args}{"\n"}{end}'
```

Do not edit `--application-namespaces` on the Deployment or StatefulSet. The operator
rewrites it on the next reconcile, which makes the fix appear to work and then regress.

### The CR is set and nothing was created

Only after confirming supported cluster scope and excluding the ownership/grant skip
conditions above, investigate reconciliation when the retained `sourceNamespaces`
entry lacks expected generated objects or workload arguments. Repeating the field
or manufacturing generated objects does not
explain the failure. First read the field back: an operator version that does not
support it may have its unknown field pruned by the API server.

```bash
$KCTL get argocd "$CR" -n "$NS" \
  -o jsonpath='sourceNamespaces={.spec.sourceNamespaces}{"\n"}phase={.status.phase}{"\n"}{range .status.conditions[*]}{.type}={.status} {.reason}: {.message} at={.lastTransitionTime}{"\n"}{end}'
$KCTL logs -n "$OP_NS" deploy/"$OP_DEPLOYMENT" -c manager --since=15m --tail=100
```

Use the operator Deployment name discovered in step 0. Quote any condition or log
that explains the missing generated state. If those reads are unavailable or do not
explain it, report reconciliation as unresolved with the evidence gap. `Available`
phase alone does not prove this setting was applied. The bundled and upstream
[`ArgoCDStatus`](https://github.com/argoproj-labs/argocd-operator/blob/v0.18.0/api/v1beta1/argocd_types.go#L943)
have no top-level `status.observedGeneration`; an empty value is not a lag signal.
Continue with Workflow 6 in `debug-workflows.md` for operator pods, CSV, InstallPlan and
conversion-webhook evidence; retain the established scope and generated-object checks.

## 3. The AppProject must permit the namespace too

This is the second half of the feature and the most common reason a correct
`sourceNamespaces` still does not work. The project the Application references must
list the namespace in **its own** `sourceNamespaces`:

```bash
# PROJ is the project from the current Application snapshot.
$KCTL get appproject "$PROJ" -n "$NS" -o jsonpath=''\
'sourceNamespaces={.spec.sourceNamespaces}{"\n"}'\
'destinations={.spec.destinations}{"\n"}'
```

The `default` project does **not** permit other namespaces out of the box. An
Application that lands in a tenant namespace and uses `project: default` fails here
with `application '<name>' in namespace '<ns>' is not permitted to use project '<project>'`.
This is Argo CD's
[`ErrProjectNotPermitted`](https://github.com/argoproj/argo-cd/blob/release-3.4/util/argo/argo.go#L1180),
which identifies project permission rather than the instance watch gate.

Both lists must permit the Application. Read both, and correlate the condition with
current reconciliation evidence. The exact project-denial message identifies the
project gate; merely finding stored status does not establish a current watch.

AppProjects are not generated by the operator, but may themselves be Git-managed.
Recommend a change to their authoritative desired state and name the layer being
corrected: AppProject policy versus the ArgoCD instance's watch configuration.

## 4. Addressing the Application afterwards

Once it works, the Application is referenced by namespace everywhere:

Addressing syntax only — this workflow is read-only and runs neither of these. Report
the form the team should use; do not sync a cluster you were asked to diagnose.

```text
argocd app get <namespace>/<application>
argocd app sync <application> --app-namespace <namespace>
```

A plain `argocd app get <name>` looks only in the instance namespace and reports the
Application as not found, which looks like the feature is still broken.

For Applications outside the instance namespace, the RBAC object is
`<project>/<namespace>/<application>`; Applications in the instance namespace retain
`<project>/<application>`. Inspect the effective policy and `policy.matchMode` before
attributing a UI/API denial to the move. An exact `team/myapp` rule will not match
`team/tenant/myapp`, but in the default glob mode `team/*` still matches both: `/` is
not a separator. Such wildcard grants may be broader than intended, not broken.

Recommend a policy change only for a demonstrated mismatch or unintended grant. On
operator-managed instances, use the authoritative `.spec.rbac.policy` input for
policy rules. The operator overwrites `argocd-rbac-cm` policy when that CR field is
set; an unset field does not guarantee reversion. Keep changes in the supported
CR/Git input rather than relying on direct ConfigMap edits to persist.

## 5. Report

State the instance scope first, then which supported layer is missing — instance
watch configuration, AppProject permission, generated state, or none. Quote the
effective configuration, freshness evidence and exact condition that distinguish them.

Recommend only the field shown to need correction, through its desired-state owner. Do not
recommend the `managed-by-cluster-argocd` label, a Role, a RoleBinding, or an edit to
`--application-namespaces`. All four are operator-reconciled, and all four will be
reverted.

Fixing source watching does not prove destination permissions. Read `operator-rbac.md`
only for independently observed destination authorization failures; otherwise close
the verified watch branch without an additional permission survey.

Version boundary: the linked operator v0.18.0 source establishes that snapshot's
scope gate; verify the installed product/operator schema and effective settings. A
retained CR field alone is not proof that the installed instance supports the feature.
