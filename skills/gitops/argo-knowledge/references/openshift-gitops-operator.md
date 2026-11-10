<!-- Loaded on demand by skills/gitops/argo-knowledge/SKILL.md. The operator-owned CRDs that
     are specific to Red Hat OpenShift GitOps — the ones with no upstream Argo CD
     equivalent. Every field below was read from the installed CRDs with
     `kubectl explain` / the CRD schema, not from memory. -->

# OpenShift GitOps Operator CRDs

Beyond `ArgoCD` itself, the OpenShift GitOps operator owns five CRDs that have **no
upstream Argo CD equivalent**. Each one replaces something you would otherwise do by hand
upstream — and in several cases, doing it by hand on OpenShift silently fails because the
operator reconciles your change away.

| Kind | API group / version | Scope | Replaces |
|------|--------------------|-------|----------|
| `RolloutManager` | `argoproj.io/v1alpha1` | Namespaced | Installing argo-rollouts yourself |
| `NotificationsConfiguration` | `argoproj.io/v1alpha1` | Namespaced | Hand-editing `argocd-notifications-cm` |
| `NamespaceManagement` | `argoproj.io/v1beta1` | Namespaced | `--application-namespaces` flag wrangling |
| `ImageUpdater` | `argocd-image-updater.argoproj.io/v1alpha1` | Namespaced | Installing + annotating for Image Updater |
| `GitopsService` | `pipelines.openshift.io/v1alpha1` | **Cluster** | (nothing — it owns the default instance) |

Confirm what a cluster actually has:

```bash
kubectl get csv -n openshift-gitops-operator -o json | \
  jq -r '.items[].spec.customresourcedefinitions.owned[]?.name' | sort -u
```

---

## RolloutManager — how Rollouts gets deployed

**On OpenShift GitOps you do not install argo-rollouts.** You create a `RolloutManager`
and the operator reconciles the controller for you. An empty spec is valid and common:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: RolloutManager
metadata:
  name: argo-rollout
  namespace: openshift-gitops
spec: {}        # valid — operator supplies controller image, version and defaults
```

Tuned:

```yaml
spec:
  namespaceScoped: false          # false = cluster-wide (watch Rollouts in all namespaces)
  ha:
    enabled: false                # HA controller (leader-elected replicas)
  controllerResources:
    requests: {cpu: 100m, memory: 128Mi}
    limits:   {cpu: 500m, memory: 512Mi}
  nodePlacement:
    nodeSelector: {node-role.kubernetes.io/infra: ""}
    tolerations: []
  networkPolicy:
    enabled: true                 # operator creates NetworkPolicies for the controller
  env:
    - name: ARGO_ROLLOUTS_LOG_LEVEL
      value: info
  extraCommandArgs: []
  plugins:                        # traffic/metric plugins, each: name, location, sha256
    trafficManagement: []
    metric: []
  # image / version / imagePullPolicy: override only to pin a non-default build
```

Full `spec` field list: `additionalMetadata`, `controllerResources`, `env`,
`extraCommandArgs`, `ha`, `image`, `imagePullPolicy`, `namespaceScoped`, `networkPolicy`,
`nodePlacement`, `plugins`, `skipNotificationSecretDeployment`, `version`. No field is
required.

**Gotchas**
- `namespaceScoped: true` makes the controller watch only its own namespace. A
  cluster-wide Rollout elsewhere will then sit untouched with no error anywhere — the
  controller simply isn't watching it.
- Only **one** cluster-scoped RolloutManager should exist per cluster. Two cluster-scoped
  controllers fight over the same Rollouts.
- Don't `kubectl edit` the `argo-rollouts` Deployment directly — the operator reverts it.
  Change the `RolloutManager`.

---

## NotificationsConfiguration — the one that bites people

**Upstream you edit `argocd-notifications-cm`. On OpenShift GitOps that ConfigMap is
operator-managed and your edits are reconciled away.** This is the single most common
OpenShift GitOps notification failure: the config looks right in Git, applies cleanly, and
then quietly disappears.

Two steps. First enable the controller on the `ArgoCD` CR:

```yaml
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  notifications:
    enabled: true      # required field — deploys argocd-notifications-controller
```

Then supply the config via the CR:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: NotificationsConfiguration
metadata:
  name: default-notifications-configuration   # see note on naming below
  namespace: openshift-gitops
spec:
  context:
    argocdUrl: https://openshift-gitops-server-openshift-gitops.apps.example.com
  services:
    service.slack: |
      token: $slack-token
  templates:
    template.app-sync-failed: |
      message: |
        Application {{.app.metadata.name}} sync failed.
        Error: {{.app.status.operationState.message}}
  triggers:
    trigger.on-sync-failed: |
      - when: app.status.operationState.phase in ['Error', 'Failed']
        send: [app-sync-failed]
  subscriptions:
    subscriptions: |
      - recipients: [slack:platform-alerts]
        triggers: [on-sync-failed]
```

**Every field is `map[string]string`** — `context`, `services`, `templates`, `triggers`
*and* `subscriptions`. Verified from the CRD schema: each is
`type: object, additionalProperties: {type: string}`. The keys are the same ones you would
put in the ConfigMap (`service.slack`, `template.<name>`, `trigger.<name>`), and the
values are the same YAML blobs as strings. Existing upstream config ports across
unchanged; only the container differs.

Note `subscriptions` is a **map**, not a bare list — a common mistake, since in the
ConfigMap form it reads as a list. Nest it under a key as shown above.

**Naming:** the operator reconciles a specific CR name — on current versions
`default-notifications-configuration` in the Argo CD instance's namespace. A CR with a
different name validates and applies cleanly but may simply be ignored. Confirm against
your operator version before assuming, and if notifications do not appear, check the name
first:

```bash
kubectl get notificationsconfiguration -n <argocd-namespace>
```

**Gotchas**
- The Secret is still a Secret. `$slack-token` resolves from
  `argocd-notifications-secret`, which you create yourself — the CR does not hold
  credentials.
- `spec.subscriptions` here is the **global** subscription list. Per-Application
  `notifications.argoproj.io/subscribe.*` annotations still work and are additive.
- If notifications silently stop after an operator upgrade, check that
  `ArgoCD.spec.notifications.enabled` is still `true` — it is easy to lose in a CR rewrite.

---

## NamespaceManagement — a two-sided handshake

Lets an Argo CD instance manage Applications in a namespace it does not own. **Both sides
must agree**, which is the part that trips people up.

Tenant side — a `NamespaceManagement` CR *in the tenant namespace*:

```yaml
apiVersion: argoproj.io/v1beta1
kind: NamespaceManagement
metadata:
  name: managed
  namespace: payments-dev
spec:
  managedBy: openshift-gitops    # REQUIRED — the Argo CD instance's namespace
```

Argo CD side — the instance must opt in:

```yaml
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  namespaceManagement:
    - name: payments-*          # name pattern; both fields are required
      allowManagedBy: true
```

`spec.managedBy` is the only field on `NamespaceManagement`, and it is required.
On the `ArgoCD` side each entry requires both `name` and `allowManagedBy`.

**Gotchas**
- **One side alone does nothing, and reports nothing.** A `NamespaceManagement` with no
  matching `ArgoCD.spec.namespaceManagement` entry is inert — no event, no condition. If a
  tenant's Applications are not being reconciled, check both sides before anything else.
- Prefer this over hand-editing `--application-namespaces`; the operator owns that flag
  and will reset it.
- This is how a tenant namespace gets attached to a central Argo CD instance. The
  `NamespaceManagement` CR and the namespace label are both desired state — commit them
  to Git and let Argo CD reconcile them rather than applying them by hand.

---

## ImageUpdater — a CRD, not just annotations

Upstream, Image Updater is configured with `argocd-image-updater.argoproj.io/*`
annotations on each Application. On OpenShift GitOps there is an operator-owned CRD —
**note the separate API group**, `argocd-image-updater.argoproj.io`, not `argoproj.io`.

**Two steps, exactly like notifications.** The CR alone does nothing — you must also turn
the controller on, or the `ImageUpdater` applies cleanly with nothing running to act on it:

```yaml
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  imageUpdater:
    enabled: true     # REQUIRED — installs the Image Updater controller
```

```yaml
apiVersion: argocd-image-updater.argoproj.io/v1alpha1
kind: ImageUpdater
metadata:
  name: image-updater
  namespace: openshift-gitops
spec:
  applicationRefs:                      # REQUIRED
    - namePattern: "payments-*"         # REQUIRED — which Applications this rule covers
      images:
        - alias: api
          imageName: registry.example.com/payments/api
          manifestTargets:
            helm:                       # for Helm sources: value keys to rewrite
              name: image.repository
              tag: image.tag
            # kustomize: {name: ...}    # for Kustomize sources — use one, not both
          commonUpdateSettings:
            updateStrategy: semver
            allowTags: "regexp:^v[0-9]+\\.[0-9]+\\.[0-9]+$"
            ignoreTags: ["latest", "dev-*"]
            pullSecret: pullsecret:openshift-gitops/registry-creds
      writeBackConfig:
        method: git
        gitConfig:
          branch: main
          writeBackTarget: kustomization
  commonUpdateSettings:                 # global defaults for all applicationRefs
    updateStrategy: semver
  writeBackConfig:
    method: git
```

- `spec.applicationRefs` is **required**; each entry requires `namePattern`.
- Per-entry fields: `namePattern`, `images[]`, `labelSelectors`, `useAnnotations`,
  `commonUpdateSettings`, `writeBackConfig`.
- `images[]` items: `alias`, `imageName`, `manifestTargets`, `commonUpdateSettings`.
- `manifestTargets` is `helm` (`name`, `tag`, `spec`) or `kustomize` (`name`).
- `writeBackConfig`: `method`, and `gitConfig` with `branch`, `repository`,
  `writeBackTarget`, `pullRequest`.

**Gotchas**
- Match `manifestTargets` to the Application's source type. Helm keys on a Kustomize
  source — or the reverse — are ignored, and the updater appears configured while writing
  nothing. Same failure mode as the annotation form.
- `useAnnotations: true` falls back to the legacy per-Application annotations, useful when
  migrating incrementally. Don't configure both for the same image.
- `write-back-method: git` needs push access. Without it, updates fail silently — check
  the image-updater controller logs, not the Application.

---

## GitopsService — why your edits keep reverting

Cluster-scoped, and it owns the **default `openshift-gitops` instance**. There is normally
exactly one, named `cluster`.

```yaml
apiVersion: pipelines.openshift.io/v1alpha1
kind: GitopsService
metadata:
  name: cluster
spec:
  runOnInfra: true                        # schedule default workloads on infra nodes
  nodeSelector:
    node-role.kubernetes.io/infra: ""
  tolerations:
    - key: node-role.kubernetes.io/infra
      effect: NoSchedule
      operator: Exists
  imagePullPolicy: IfNotPresent
  consolePlugin:                          # OpenShift console GitOps plugin
    gitopsPlugin: {}
    backend: {}
```

**The important part is ownership.** The default `openshift-gitops` ArgoCD CR carries an
ownerReference back to `GitopsService/cluster` with `blockOwnerDeletion: true`:

```bash
kubectl get argocd openshift-gitops -n openshift-gitops \
  -o jsonpath='{.metadata.ownerReferences}'
```

So:
- Manual edits to the **default** instance's ArgoCD CR may be reverted by the operator.
  For durable cluster-wide changes (infra node placement, tolerations, pull policy), set
  them on `GitopsService` instead.
- Deleting `GitopsService/cluster` tears down the default instance.
- If you need a freely-editable instance, create your **own** `ArgoCD` CR in a separate
  namespace rather than fighting the default one. That is also why multi-instance clusters
  are common on OpenShift — check `kubectl get argocd -A` before assuming there is one.

---

## Which CR owns which setting

The recurring question when something will not stay changed:

| You want to change | Set it on | Not on |
|--------------------|-----------|--------|
| Argo CD component replicas, resources, SSO, RBAC, route | `ArgoCD` CR | the Deployments |
| Resource tracking method (`label` / `annotation`) | **`ArgoCD.spec.resourceTrackingMethod`** | `resource.trackingMethod` in `argocd-cm` — reconciled away |
| Notification templates/triggers/services | `NotificationsConfiguration` | `argocd-notifications-cm` |
| Whether the notifications controller runs at all | `ArgoCD.spec.notifications.enabled` | — |
| Rollouts controller image, HA, resources, scope | `RolloutManager` | the argo-rollouts Deployment |
| Which namespaces an instance may manage | `NamespaceManagement` **and** `ArgoCD.spec.namespaceManagement` | `--application-namespaces` |
| Whether the Image Updater controller runs at all | `ArgoCD.spec.imageUpdater.enabled` | — |
| Image update rules | `ImageUpdater` CR (or legacy annotations) | — |
| Infra node placement for *default* workloads | `GitopsService` | the default `ArgoCD` CR |

**The general rule on OpenShift GitOps: if the operator owns the resource, edit the CR,
not the resource.** A direct edit applies cleanly, survives until the next reconcile, and
then vanishes — which reads as a mysterious regression rather than a configuration error.

## Repository credentials — where they live, and who should rotate them

Argo CD stores repository credentials as labelled Secrets in the Argo CD namespace, not
in the `ArgoCD` CR. Two labels, and the difference matters:

| Label | Scope |
|---|---|
| `argocd.argoproj.io/secret-type: repository` | One specific repo, matched on its `url` key |
| `argocd.argoproj.io/secret-type: repo-creds` | A URL *prefix* — credentials inherited by every repo underneath it |

```bash
# What exists, without printing any credential material
kubectl get secrets -n "$NS" \
  -l 'argocd.argoproj.io/secret-type in (repository,repo-creds)' \
  -o custom-columns='NAME:.metadata.name,TYPE:.metadata.labels.argocd\.argoproj\.io/secret-type'

# Which repo a given Secret is for — the url key is not sensitive
kubectl get secret <name> -n "$NS" -o jsonpath='{.data.url}' | base64 -d
```

A `repo-creds` entry is the usual surprise during an incident: a repo that appears to
have no credentials of its own is inheriting them from a prefix entry, so rotating the
`repository` Secret alone changes nothing.

### Rotation belongs in a secrets manager, not in an ad-hoc edit

**Do not hand-rotate these Secrets, and do not ask an agent to.** Desired state belongs
in Git and credential material belongs in a secrets-management system — the same
position `argo-repo-audit` takes when it flags hardcoded secrets. Use **External Secrets
Operator**, **Vault**, or **Sealed Secrets**: rotate at the provider, let the controller
reconcile the Secret, and let Argo CD pick it up.

The failure mode that makes this worth stating: a credential that applies cleanly and
cannot authenticate. The apply succeeds, `kubectl` reports `configured`, and nothing is
visibly wrong until every Application on that repo starts failing to refresh. A typo'd
rotation locks Argo CD out of the repo it needs to self-heal from.

### Verifying a rotation actually worked

Whatever performed the rotation, the check is the same — and it is a connectivity test,
not a diff. A Secret can be perfectly well-formed and still be rejected.

```bash
# Connection state as Argo CD sees it
kubectl get secret <name> -n "$NS" \
  -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/connection-status}{"\n"}'

# Or, where the argocd CLI is available (it is not, in the agentic sandbox)
argocd repo get <repo-url>
```

Then confirm an Application that uses the repo can still refresh:

```bash
kubectl patch applications.argoproj.io <app> -n "$NS" --type=merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
kubectl get applications.argoproj.io <app> -n "$NS" \
  -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}{"\n"}'
```

An empty `ComparisonError` after a hard refresh is the evidence that the credential
works. Never echo token values into logs or transcripts while checking — the `url` and
`connection-status` fields answer the question without exposing the secret.
