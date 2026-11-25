# Debugging workflows

Read only the matching workflow. Reuse evidence and successfully read references as
specified in `../SKILL.md`; examples request missing evidence, not repeated surveys.
`APP_NS` is the Application namespace; `NS` is the owning instance namespace.
`APPSET_NS` is the ApplicationSet namespace. Neither is necessarily the destination.
Initialize variables from observed evidence in each fresh shell.

## Workflow 1: Argo CD installation and ownership

Use for installation questions, unresolved ownership, or suspected component failure.
A known workload failure does not require all these checks.

1. Start with the requested Application/namespace and existing installation evidence.
   For an operator-managed instance, inspect the candidate ArgoCD CR and generated
   workload/ConfigMap owner references. Discover candidates only when unknown:

   ```bash
   $KCTL get argocds.argoproj.io -A \
     -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase
   ```

   Preserve Forbidden, NotFound and unsupported-resource errors separately. A denied
   CR read is not a standalone installation. Never pick `items[0]`. If operator CRs
   are unavailable, inspect accessible Deployments/StatefulSets in candidate namespaces;
   a cluster-wide workload inventory is a last discovery step, not a prerequisite.
   Helm names and labels vary. A namespace matching the Application is a candidate,
   not proof of ownership: Apps in Any Namespace can be enabled. Use
   `operator-apps-in-any-namespace.md` when watch ownership is unclear. Report findings
   separately when several instances remain possible.

2. Inspect the actual workloads once in the established namespace:

   ```bash
   $KCTL get deploy,sts -n "$NS" \
     -o custom-columns=KIND:.kind,NAME:.metadata.name,OWNER:.metadata.ownerReferences,READY:.status.readyReplicas,WANT:.spec.replicas
   ```

   Confirm the owner, component image and selector before using a name. Operator names
   often contain the CR name but suffix/prefix matching alone is not ownership proof.
   Read the selected workload's selector, containers and readiness in one query:

   ```bash
   $KCTL get <deployment-or-statefulset> <observed-name> -n "$NS" \
     -o jsonpath='owners={.metadata.ownerReferences}{"\n"}selector={.spec.selector}{"\n"}{range .spec.template.spec.containers[*]}container={.name} image={.image}{"\n"}{end}conditions={.status.conditions}{"\n"}'
   ```

   Check only components required by the configured installation: application-controller,
   repo-server and cache for normal reconciliation; server for UI/API (not Argo CD Core);
   ApplicationSet controller when enabled/used; Dex only for Dex-backed SSO (not direct
   OIDC); notifications only when configured. Zero replicas or an intentionally disabled
   optional component is not automatically a fault. For failing components use Workflow 5.

3. Establish version only when it affects the diagnosis. An authenticated `argocd
   version` can report the remote server; core-mode CLI output is not independent
   operand-version evidence. For the identified operator instance, inspect its reported
   version and workload images; retain digests as build identifiers, not version numbers:

   ```bash
   $KCTL get argocds.argoproj.io "$CR" -n "$NS" \
     -o jsonpath='version={.status.version}{"\n"}phase={.status.phase}{"\n"}'
   ```

   Operator CSV version identifies the operator, not necessarily the exact Argo CD
   operand. Correlate release metadata with the image/build; otherwise say version
   unverified. Missing optional status fields do not prove the installation is broken.

4. Read configuration only for the selected hypothesis: health customizations,
   Kustomize/CMP settings, server URL, or server RBAC policy/scopes. Project individual
   keys rather than dumping `argocd-cm`/`argocd-rbac-cm`; legacy repository configuration
   can contain credentials. Use Workflow 6 for operator reconciliation evidence.

5. If installation itself is unresolved, check the relevant CRDs explicitly:

   ```bash
   $KCTL get crd applications.argoproj.io appprojects.argoproj.io
   # Only when ApplicationSet support is relevant:
   $KCTL get crd applicationsets.argoproj.io
   ```

   Missing ApplicationSet support alone does not establish that Argo CD is absent.
   Separate a confirmed missing API from inaccessible discovery or a remote Argo CD
   installation managing this destination cluster.

## Workflow 2: Application evidence and routing

For known symptoms use the direct route in `../SKILL.md`. Otherwise fetch the missing
Application state in one read, omitting fields already captured:

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath=''\
'uid={.metadata.uid} observedAt={.status.reconciledAt}{"\n"}'\
'project={.spec.project} destination={.spec.destination}{"\n"}'\
'sync={.status.sync.status} health={.status.health.status} healthMessage={.status.health.message}{"\n"}'\
'phase={.status.operationState.phase} started={.status.operationState.startedAt} finished={.status.operationState.finishedAt}{"\n"}'\
'opMessage={.status.operationState.message}{"\n"}'\
'automated={.spec.syncPolicy.automated}{"\n"}'\
'comparedRevision={.status.sync.revision} comparedRevisions={.status.sync.revisions}{"\n"}'\
'operationRevision={.status.operationState.syncResult.revision} operationRevisions={.status.operationState.syncResult.revisions}{"\n"}'\
'{range .status.conditions[*]}condition={.type}: {.message}{"\n"}{end}'
```

A lookup failure goes to `resource-lookup.md`. Do not infer health from sync status or
from an old operation result. Use `app-health-triage.md` or `app-sync-triage.md` only
when status selection/semantics need explanation; known states go directly to the
leaf. Operator authorization and watching use their respective operator guides.
Use `resource-health.md` when per-resource assessments are needed and not yet known.

For source/revision questions, select each source's repoURL, targetRevision, path,
chart, ref and relevant renderer settings; see `sync-comparison-error.md`. For current
resource drift use `sync-outofsync.md`; a resource status list is not a manifest diff.
Preserve independent findings, then use the entry's report route. No generic follow-up
survey is needed once the selected procedures establish the causes.

---

## Workflow 3: ApplicationSet Debugging

Use when: user reports ApplicationSet not generating Applications, generating wrong Applications, or ApplicationSet errors.

**Steps:**

1. Get the ApplicationSet:
   ```bash
   kubectl get applicationset <name> -n "$NS" -o yaml
   ```

2. Check `.status.conditions` for errors. Key conditions:
   - `ErrorOccurred` — generator or template rendering failed
   - `ParametersGenerated` — generator output status
   - `ResourcesUpToDate` — template application status

3. Identify the generator type and check its configuration:
   | Generator | Common Issues |
   |-----------|--------------|
   | list | Empty `elements` array |
   | git (directories) | `repoURL` inaccessible, `directories` path pattern wrong |
   | git (files) | File format invalid, path pattern wrong |
   | cluster | No matching clusters, label selector wrong |
   | pull request | API credentials missing/expired, no open PRs matching filter |
   | scmProvider | API credentials missing, org/owner wrong |
   | matrix/merge | Inner generator errors, key conflicts |
   | plugin | Plugin ConfigMap missing, generator RPC error |

4. List generated Applications:
   ```bash
   kubectl get applications.argoproj.io -n "$NS" -l 'app.kubernetes.io/managed-by=applicationset-controller' --show-labels
   ```
   Cross-reference with expected output from the generator.

5. If no Applications generated, check the applicationset-controller logs:
   ```bash
   kubectl logs -n "$NS" -l app.kubernetes.io/name=$CR-applicationset-controller --tail=200
   ```

6. If generated Applications are failing, read the matching Workflow 2 reference
   in `../SKILL.md` for each Application; reuse the installation evidence.

7. For progressive sync issues, check `spec.strategy`:
   ```bash
   kubectl get applicationset <name> -n "$NS" -o jsonpath='{.spec.strategy}' | { read -r s || true; [ -n "$s" ] \
     && printf '%s' "$s" | python3 -m json.tool \
     || echo 'no spec.strategy set — this ApplicationSet syncs AllAtOnce'; }
   ```
   Check `rollingSync.steps`, `maxUpdate` values, and whether unhealthy apps are blocking progression.

   **First, check that progressive syncs are switched on at all — on OpenShift GitOps
   they are not by default.** `RollingSync` is a no-op unless the applicationset
   controller runs with `--enable-progressive-syncs`. Without it the strategy block is
   accepted, stored, and **completely ignored**: every Application syncs AllAtOnce while
   the ApplicationSet still shows `ResourcesUpToDate=True` and reports no error anywhere.

   ```bash
   # The flag (operator installs do NOT set it by default). Note the label is NOT
   # prefixed with the CR name, and `range` is used so an empty result prints nothing
   # instead of crashing with "array index out of bounds" the way .items[0] does.
   $KCTL get deploy -n "$NS" -l app.kubernetes.io/name=argocd-applicationset-controller \
     -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.template.spec.containers[0].command}{"\n"}{end}'

   # The tell: RollingSync populates .status.applicationStatus. An empty value or `[]`
   # alongside a declared rollingSync strategy means the strategy is not running.
   $KCTL get applicationset <name> -n "$NS" -o jsonpath='{.status.applicationStatus}{"\n"}'
   ```

   Verified on OpenShift GitOps 1.21.3: an ApplicationSet declaring two `rollingSync`
   steps had an empty `.status.applicationStatus`, and both generated Applications
   reached `Synced` at the **same revision** — the production app was never gated behind
   a staging app that never became Healthy.

   To enable it, set `spec.applicationSet.extraCommandArgs: ["--enable-progressive-syncs"]`
   on the **`ArgoCD` CR**, not on the Deployment — the operator reverts direct Deployment
   edits. Expect the controller to restart.

   Only once the flag is on do the usual causes apply: a step whose `matchExpressions`
   match no Application (that step completes vacuously), `maxUpdate` saturated by apps
   that never converge, or an earlier step whose apps never reach Healthy.

---

## Workflow 4: Rollout Debugging

Use when: user reports canary/blue-green rollout stuck, aborted, or degraded.

**Steps:**

1. Get the Rollout status:
   - kubectl-argo-rollouts:
     ```bash
     kubectl argo rollouts get rollout <name> -n <namespace>
     ```
   - kubectl:
     ```bash
     kubectl get rollout <name> -n <namespace> -o yaml
     ```

2. Check the phase from `.status.phase`:
   | Phase | Meaning |
   |-------|---------|
   | Healthy | Rollout completed successfully |
   | Paused | Waiting for manual promotion or analysis |
   | Progressing | Actively rolling out |
   | Degraded | Rollout encountered errors |
   | Aborting | Rollback in progress |
   | Aborted | Rollback completed |

3. For canary rollouts, check current step and step index:
   ```bash
   kubectl get rollout <name> -n <namespace> -o jsonpath='{.status.currentStepIndex}'
   kubectl get rollout <name> -n <namespace> -o jsonpath='{.spec.strategy.canary.steps}'
   ```
   Identify which step the rollout is paused/stuck at.

   **Resolve the numbering before you answer.** `.status.currentStepIndex` is a
   **0-based index into `spec.strategy.canary.steps`**, while users almost always count
   steps from 1 — so "stuck at step 2" usually means `currentStepIndex: 1`, and an index
   of 2 is the user's "step 3". The two readings point at different steps and therefore
   different root causes. State the mapping explicitly, e.g.:

   > `currentStepIndex: 1` → `steps[1]` = `pause: {duration: 30s}` — your "step 2".

   If the user's wording is ambiguous, print the whole list with both numberings and say
   which one you diagnosed. An index equal to `len(steps)` means every step completed.

4. If paused, determine the reason:
   - `pause` step: manual approval required. Check `.status.pauseConditions`.
   - `analysis` step: AnalysisRun in progress. Proceed to step 5.
   - `setWeight` step: traffic shift issue. Proceed to step 8.

5. Get AnalysisRuns for this Rollout:
   ```bash
   kubectl get analysisrun -n <namespace> --sort-by='.metadata.creationTimestamp'
   ```
   Filter by Rollout ownership:
   ```bash
   kubectl get analysisrun -n <namespace> -o yaml | grep -A5 'ownerReferences' | grep '<rollout-name>'
   ```
   Or use the revision label:
   ```bash
   kubectl get analysisrun -n <namespace> -l rollouts-pod-template-hash=<hash>
   ```

6. Inspect the AnalysisRun:
   ```bash
   kubectl get analysisrun <analysisrun-name> -n <namespace> -o yaml
   ```
   Check:
   - `.status.phase` — Running, Successful, Failed, Error, Inconclusive
   - `.status.metricResults[*].phase` — per-metric status
   - `.status.metricResults[*].measurements` — individual measurement values
   - `.status.metricResults[*].message` — error messages from the provider

7. If analysis failed, check the AnalysisTemplate:
   ```bash
   kubectl get analysistemplate <template-name> -n <namespace> -o yaml
   ```
   Verify:
   - `successCondition` / `failureCondition` expressions
   - `provider` configuration (Prometheus URL, Datadog API key, web query, etc.)
   - `interval`, `count`, `failureLimit`, `inconclusiveLimit`

8. Check traffic management configuration:
   - Istio:
     ```bash
     kubectl get virtualservice -n <namespace> -o yaml
     kubectl get destinationrule -n <namespace> -o yaml
     ```
   - NGINX Ingress:
     ```bash
     kubectl get ingress -n <namespace> -o yaml
     ```
     Check `canary-*` annotations.
   - ALB:
     ```bash
     kubectl get ingress -n <namespace> -o yaml
     ```
     Check `alb.ingress.kubernetes.io/*` annotations.
   - Traefik:
     ```bash
     kubectl get traefikservice -n <namespace> -o yaml
     ```

8b. **Blue-green: there are no steps, so "stuck" means something different.** A
    blue-green Rollout has no `steps` array and no `currentStepIndex`, and it never
    progresses on its own the way canary does between `setWeight`/`pause` entries. It
    moves preview → active on exactly one trigger:

    | | canary | blue-green |
    |---|---|---|
    | progression | automatic through `steps[]`, pausing only where told | single promotion event, no intermediate steps |
    | what "stuck" means | sitting at one `steps[]` entry | preview is up and promotion never fired |
    | usual cause | a `pause` with no duration, or a failing `analysis` step | `autoPromotionEnabled: false` was set explicitly and nobody promoted, a failing/running `prePromotionAnalysis`, or the new ReplicaSet never became Healthy |

    So do not look for a step index on a blue-green Rollout — check, in order:
    ```bash
    kubectl get rollout <name> -n <namespace> \
      -o jsonpath='{.spec.strategy.blueGreen.autoPromotionEnabled}{"\n"}{.status.pauseConditions}{"\n"}'
    ```
    **`autoPromotionEnabled` defaults to `true`** — an unset field means the rollout
    *should* self-promote as soon as the new ReplicaSet is Healthy. So an unset field is
    a red flag pointing at the ReplicaSet or at analysis, whereas an explicit
    `autoPromotionEnabled: false` is **intended behaviour**: the rollout is waiting for
    `kubectl argo rollouts promote <name>`, and you should report it as such rather than
    as a fault. (`autoPromotionSeconds` only applies in that paused state — it promotes
    automatically once that many seconds have elapsed; it defaults to nil, meaning never.)

9. Check ReplicaSets — compare stable vs canary:
   ```bash
   kubectl get replicaset -n <namespace> -l app=<app-label> -o wide
   ```
   The stable RS has the `rollouts-pod-template-hash` matching `.status.stableRS`, canary RS matches `.status.currentPodHash`.

10. Check pod status for the canary ReplicaSet:
    ```bash
    kubectl get pods -n <namespace> -l rollouts-pod-template-hash=<canary-hash>
    kubectl describe pods -n <namespace> -l rollouts-pod-template-hash=<canary-hash>
    ```

11. Produce a root cause analysis report.

---

## Workflow 5: Component logs

Use the already identified Deployment, StatefulSet or Pod and its actual selector.
The application-controller may be a StatefulSet; do not require a Deployment.
If unresolved, use Workflow 1's scoped workload inventory, not guessed label prefixes.

```bash
$KCTL get pods -n "$NS" -l "$COMPONENT_SELECTOR" \
  -o custom-columns=NAME:.metadata.name,OWNER:.metadata.ownerReferences,CONTAINERS:.spec.containers[*].name,STATE:.status.containerStatuses[*].state,RESTARTS:.status.containerStatuses[*].restartCount
$KCTL logs "$POD" -n "$NS" -c "$CONTAINER" --since=15m --tail=200
# Only for a restarted container; widen the window for an older incident:
$KCTL logs "$POD" -n "$NS" -c "$CONTAINER" --previous --tail=100
```

Correlate timestamps and Application/resource identity with errors, stack traces,
connection failures, authorization denials and OOM/restart evidence. A historical
restart count does not establish a current outage. Filter relevant context before
returning large logs; retain enough surrounding lines to distinguish the cause.

## Workflow 6: Operator / OLM reconciliation

Use for an unapplied supported CR setting, failed upgrade, or operator-generated
objects missing despite valid inputs. First distinguish authoritative Git reversion,
unsupported configuration/scope and actual reconciliation failure. For destination
or source-namespace issues use the respective operator guide.

Identify the owning operator namespace, Subscription, installed/current CSV and
referenced InstallPlan; do not select the first item or diagnose another operator.
Use existing evidence or list compact names/references once, then inspect the selected
objects (example variables must be initialized in each execution):

```bash
$KCTL get subscriptions.operators.coreos.com "$SUB" -n "$OP_NS" \
  -o jsonpath='installedCSV={.status.installedCSV} currentCSV={.status.currentCSV} plan={.status.installPlanRef.name}{"\n"}conditions={.status.conditions}{"\n"}'
$KCTL get csv "$CSV" -n "$OP_NS" \
  -o jsonpath='version={.spec.version} phase={.status.phase} reason={.status.reason}{"\n"}message={.status.message}{"\n"}'
$KCTL get installplan "$PLAN" -n "$OP_NS" \
  -o jsonpath='phase={.status.phase} approved={.spec.approved}{"\n"}conditions={.status.conditions}{"\n"}'
```

Skip absent references rather than issuing empty-name reads. Correlate failed or
pending upgrade conditions with the selected operator's current readiness and recent
logs. Subscription `AtLatestKnown` alone does not prove upgrade success; a CSV being
replaced or historical restarts alone do not prove all reconciliation is broken.

Only when request errors implicate conversion, inspect the ArgoCD CRD:

```bash
$KCTL get crd argocds.argoproj.io \
  -o jsonpath='strategy={.spec.conversion.strategy}{"\n"}client={.spec.conversion.webhook.clientConfig}{"\n"}versions={.spec.versions[*].name}{"\n"}stored={.status.storedVersions}{"\n"}'
```

`strategy: None` needs no conversion webhook. For `Webhook`, verify the failing
request actually needs conversion and correlate service/endpoints, trust and TLS
errors. A custom `caBundle` is optional when system trust suffices; an empty value is
not proof every write fails. Do not issue a test mutation during diagnosis.

Report the observed blocker, its affected instance/operation, and remaining unknowns.
Use Workflow 1 only if an additional installation question remains unresolved.
Source: [Kubernetes CRD conversion](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definition-versioning/).
