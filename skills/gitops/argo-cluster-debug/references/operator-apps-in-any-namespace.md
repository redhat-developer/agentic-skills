<!-- Loaded on demand by operator-troubleshooting.md when an Application
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
| Operator then | Grants the instance rights on `applications.argoproj.io` in that namespace, and labels it `argocd.argoproj.io/managed-by-cluster-argocd` | Creates the destination Role and RoleBinding for the controller and server |
| Symptom when missing | The Application is ignored entirely — no status, not in the UI | The Application syncs and fails `forbidden` |

If the Application has no current reconciliation evidence, investigate its watch
scope here. If a current sync is `forbidden`, continue with `operator-rbac.md`.

## 0. Confirm the instance supports this feature

Read `ARGOCD_CLUSTER_CONFIG_NAMESPACES` from the operator Deployment's effective
environment, not just an optional Subscription override:

```bash
$KCTL get deploy -n openshift-gitops-operator \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.template.spec.containers[?(@.name=="manager")].env[*]}{.name}={.value}{"\n"}{end}{end}'
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
field. Inspect the generated objects rather than inferring success from the CR alone:

```bash
# The operator labels each permitted namespace.
$KCTL get ns "$APP_NS" \
  -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/managed-by-cluster-argocd}{"\n"}'

# And grants the instance rights on Application objects there.
$KCTL get role,rolebinding -n "$APP_NS" | grep -i argocd
```

The label value is the Argo CD **namespace**. Do not set this label by hand — the
operator derives it from `sourceNamespaces` and will remove a hand-written one that
does not correspond to a CR entry.

Confirm the flag reached the workloads. The operator renders `sourceNamespaces` into
the controller and server arguments, and a CR that was edited but never reconciled is
visible here:

```bash
$KCTL get statefulset "$CR"-application-controller -n "$NS" \
  -o jsonpath='{.spec.template.spec.containers[0].command}{"\n"}' | tr ',' '\n' | grep -i namespaces
$KCTL get deploy "$CR"-server -n "$NS" \
  -o jsonpath='{.spec.template.spec.containers[0].command}{"\n"}' | tr ',' '\n' | grep -i namespaces
```

Do not edit `--application-namespaces` on the Deployment or StatefulSet. The operator
rewrites it on the next reconcile, which makes the fix appear to work and then regress.

### The CR is set and nothing was created

Only after confirming supported cluster scope, if `sourceNamespaces` still contains
the namespace but the label, RBAC and workload arguments are absent, investigate
reconciliation. Repeating the field or manufacturing generated objects does not
explain the failure. First read the field back: an operator version that does not
support it may have its unknown field pruned by the API server.

```bash
$KCTL get argocd "$CR" -n "$NS" \
  -o jsonpath='sourceNamespaces={.spec.sourceNamespaces}{"\n"}phase={.status.phase}{"\n"}{range .status.conditions[*]}{.type}={.status} {.reason}: {.message} at={.lastTransitionTime}{"\n"}{end}'
$KCTL logs -n openshift-gitops-operator deploy/<operator-deployment> -c manager --tail=100
```

Use the operator Deployment name discovered in step 0. Quote any condition or log
that explains the missing generated state. If those reads are unavailable or do not
explain it, report reconciliation as unresolved with the evidence gap. `Available`
phase alone does not prove this setting was applied. The bundled and upstream
[`ArgoCDStatus`](https://github.com/argoproj-labs/argocd-operator/blob/v0.18.0/api/v1beta1/argocd_types.go#L943)
have no top-level `status.observedGeneration`; an empty value is not a lag signal.
Continue with Workflow 6 in `../SKILL.md` for operator pods, CSV, InstallPlan and
conversion-webhook evidence; retain the established scope and generated-object checks.

## 3. The AppProject must permit the namespace too

This is the second half of the feature and the most common reason a correct
`sourceNamespaces` still does not work. The project the Application references must
list the namespace in **its own** `sourceNamespaces`:

```bash
PROJ=$($KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath='{.spec.project}')
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

This also changes RBAC policy strings. With `sourceNamespaces` in play, the object in
an `applications` policy rule becomes `<project>/<namespace>/<application>` instead of
`<project>/<application>`. Existing two-part rules stop matching the Applications that
moved, so a working RBAC policy silently narrows at the moment this feature is enabled.
Nothing logs an error, because a non-match is not a failure. The fix is
`.spec.rbac.policy` on the `ArgoCD` CR — the operator renders `argocd-rbac-cm` from it,
so a direct ConfigMap edit is reverted on the next reconcile.

## 5. Report

State the instance scope first, then which supported layer is missing — instance
watch configuration, AppProject permission, generated state, or none. Quote the
effective configuration, freshness evidence and exact condition that distinguish them.

Recommend only the field shown to need correction, through its desired-state owner. Do not
recommend the `managed-by-cluster-argocd` label, a Role, a RoleBinding, or an edit to
`--application-namespaces`. All four are operator-reconciled, and all four will be
reverted.

Finally, inspect destination authorization separately. Fixing source watching does
not prove the controller can create the requested workload kind; `operator-rbac.md`
distinguishes cluster-scoped rights, namespace grants, remote targets and project policy.
