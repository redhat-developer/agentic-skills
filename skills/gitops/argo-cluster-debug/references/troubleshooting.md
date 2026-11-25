# Component troubleshooting

Use only for an inconclusive specialized check or a component-specific symptom.
Reuse instance ownership, observed workload selectors and evidence from `../SKILL.md`.
`APP_NS` is the Application namespace; `NS` is the instance namespace. Do not choose
the first CR, assume a standalone prefix, or infer absence from a denied read.

## Application sync issues

Read the direct procedure; do not run a second generic sync checklist:

| Signal | Reference |
|---|---|
| `ComparisonError` with `error setting app health` | `health-unknown.md` |
| Repository authentication, manifest generation, invalid spec, comparison unavailable | `sync-comparison-error.md` |
| Destination controller authorization | `operator-rbac.md` |
| Ignored Application / source-namespace access | `operator-apps-in-any-namespace.md` |
| OutOfSync without a running operation | `sync-outofsync.md` |
| Failed operation | `sync-failed.md` |
| Running or Terminating operation | `sync-stuck.md` |
| Synced but unexpected state | `sync-false-synced.md` |
| Status selection unresolved | `app-sync-triage.md` |

For repo-server timeouts, distinguish repository connectivity, renderer execution,
and controller/server RPC deadlines from their actual error messages. Inspect the
relevant effective configuration and running version; do not assume all `rpc error`
messages mean OOM or increase a timeout without evidence. Controller capacity issues
can require `../../argo-performance-tuning/SKILL.md`.

## Health Check Issues

Use [Application health triage](app-health-triage.md) for health-assessment rules,
Application rollup semantics, and status selection. The specialized guides below own
the diagnostic procedures; read the matching guide before choosing checks.

Before filtering per-resource health, follow
[resource health retrieval](resource-health.md) or reuse its successful current-run
snapshot. Missing inline health fields are not findings.

| Signal | Required reference |
|--------|--------------------|
| `Degraded` | [Degraded health](health-degraded.md) |
| Sustained `Progressing` | [Progressing health](health-progressing.md) |
| `Missing` | [Missing health](health-missing.md) |
| Health `Unknown` | [Unknown health](health-unknown.md) |
| Status unclear or aggregate health unexplained | [Application health triage](app-health-triage.md) |

Continue any independent sync or operator findings through the matching route in
[the parent skill](../SKILL.md). Completing health triage does not close those findings.

---

## ApplicationSet Issues

### No Applications generated

**Symptoms:** ApplicationSet exists but `kubectl get applications.argoproj.io -n "$NS"` shows none owned by it.

**Causes:**
- Generator returns an empty parameter set
- For `git` generators: repository path doesn't match any directories/files
- For `cluster` generators: no clusters match the label selector
- For `scmProvider`/`pullRequest` generators: API credentials are missing or expired
- Template has invalid syntax — applicationset-controller silently drops errors in some versions
- RBAC: applicationset-controller ServiceAccount can't list clusters or access SCM API

**Debug:**
```bash
# Check applicationset-controller logs
kubectl logs -n "$NS" -l app.kubernetes.io/name=$CR-applicationset-controller --tail=200

# Check ApplicationSet status
kubectl get applicationset <name> -n "$NS" -o jsonpath='{.status}' | python3 -m json.tool

# For cluster generator: list known clusters
argocd cluster list
# or
kubectl get secrets -n "$NS" -l argocd.argoproj.io/secret-type=cluster
```

### Duplicate Applications

**Symptoms:** Multiple Applications with the same name or targeting the same destination.

**Causes:**
- Overlapping generators (e.g., two `list` generators producing the same parameters)
- Missing `goTemplate: true` with incorrect `name` template producing duplicates
- Matrix generator with non-unique key combinations

**Debug:**
```bash
# List applications and their owning ApplicationSet
kubectl get applications.argoproj.io -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}: {.metadata.ownerReferences[0].name}{"\n"}{end}'
```

### Applications not updating after generator source changes

**Symptoms:** Changes to the generator source (e.g., new directory in git repo, new cluster) are not reflected.

**Causes:**
- Generator caching — SCM/PR generators cache API responses (default varies)
- `requeueAfterSeconds` not set or set too high
- applicationset-controller not reconciling — check its logs for errors

**Debug:**
```bash
# Check requeueAfterSeconds
kubectl get applicationset <name> -n "$NS" -o jsonpath='{.spec.generators[*].scmProvider.requeueAfterSeconds}'
```

Compare generator inputs, conditions and recent controller logs; do not force a
refresh by mutating the ApplicationSet during diagnosis.

### Progressive sync stuck

**Symptoms:** ApplicationSet with `spec.strategy.type: RollingSync` is not progressing through steps.

**Causes:**
- `maxUpdate` value is blocking — all allowed slots are occupied by unhealthy apps
- An Application in an earlier step is Degraded, blocking progression
- `matchExpressions` in step selectors don't match any Applications

**Debug:**
```bash
# Check strategy configuration
kubectl get applicationset <name> -n "$NS" -o jsonpath='{.spec.strategy}' | python3 -m json.tool

# Check Application health per step
kubectl get applications.argoproj.io -n "$NS" -l 'app.kubernetes.io/managed-by=applicationset-controller' -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
```

---

## Rollout Issues

### Canary stuck at a step

**Symptoms:** Rollout shows `Paused` phase with a step index that doesn't advance.

**Causes:**
- Current step is a `pause` step with `duration: {}` (indefinite) — requires manual promotion
- Current step is `analysis` — AnalysisRun is still running or has failed
- Current step is `setWeight` — traffic management configuration is incorrect
- `setCanaryScale` step specifying explicit replicas but not enough nodes/resources

**Debug:**
```bash
# Get current step index and steps
kubectl get rollout <name> -n <namespace> -o jsonpath='Step {.status.currentStepIndex}: {.spec.strategy.canary.steps[*]}'

# Check pause conditions
kubectl get rollout <name> -n <namespace> -o jsonpath='{.status.pauseConditions}'

# For manual promotion (if requested by user):
kubectl argo rollouts promote <name> -n <namespace>
```

### Blue-green not promoting

**Symptoms:** Rollout shows `Paused` in blue-green mode. Preview stack is running but active is not updated.

**Causes:**
- `autoPromotionEnabled: false` — requires manual promotion
- `prePromotionAnalysis` is failing — AnalysisRun for pre-promotion metrics has failed
- `autoPromotionSeconds` not elapsed yet
- `scaleDownDelaySeconds` causing old ReplicaSet to linger (not a failure, just slow cleanup)

**Debug:**
```bash
# Check blue-green configuration
kubectl get rollout <name> -n <namespace> -o jsonpath='{.spec.strategy.blueGreen}' | python3 -m json.tool

# Check active vs preview services
kubectl get rollout <name> -n <namespace> -o jsonpath='active={.status.blueGreen.activeSelector}, preview={.status.blueGreen.previewSelector}'

# Check preview service endpoints
kubectl get endpoints <preview-service> -n <namespace>
```

### AnalysisRun inconclusive

**Symptoms:** AnalysisRun phase is `Inconclusive`. Rollout may be paused or aborted depending on `inconclusiveLimit`.

**Causes:**
- Metrics provider returned no data (query returned empty result set)
- Prometheus query returns `NaN` or no timeseries
- `successCondition` and `failureCondition` both evaluate to false
- Measurement `startedAt` was before canary pods were ready (no metrics to scrape)

**Debug:**
```bash
# Check metric results
kubectl get analysisrun <name> -n <namespace> -o jsonpath='{range .status.metricResults[*]}metric={.name}, phase={.phase}, measurements={.count}{"\n"}{end}'

# Get the actual measurement values
kubectl get analysisrun <name> -n <namespace> -o jsonpath='{.status.metricResults[0].measurements}' | python3 -m json.tool

# Check the AnalysisTemplate provider config
kubectl get analysistemplate <template> -n <namespace> -o yaml
```

### Traffic split not working

**Symptoms:** Canary weight is set but traffic is not actually shifting. All traffic goes to stable.

**Causes:**
- Istio VirtualService not found or not owned by the Rollout
- Istio VirtualService `host` doesn't match the Rollout's canary/stable services
- NGINX Ingress: `nginx.ingress.kubernetes.io/canary: "true"` annotation missing on canary Ingress
- ALB: target group binding not configured
- Rollout's `spec.strategy.canary.trafficRouting` references a service that doesn't exist

**Debug:**
```bash
# Check traffic routing config on Rollout
kubectl get rollout <name> -n <namespace> -o jsonpath='{.spec.strategy.canary.trafficRouting}' | python3 -m json.tool

# For Istio: check VirtualService weights
kubectl get virtualservice <vs-name> -n <namespace> -o jsonpath='{.spec.http[0].route}'

# Verify services exist
kubectl get svc <stable-service> <canary-service> -n <namespace>
```

### ScaleDown delay — preview/canary pods lingering

**Symptoms:** After promotion, old ReplicaSet pods remain running.

**Causes:**
- `scaleDownDelaySeconds` is set (default: 30 for canary, 30 for blue-green) — this is intentional to drain connections
- `abortScaleDownDelaySeconds` for aborted rollouts
- Finalizer on the ReplicaSet preventing scale-down

**Debug:**
```bash
# Check scale-down delay config
kubectl get rollout <name> -n <namespace> -o jsonpath='{.spec.strategy.canary.scaleDownDelaySeconds}'
kubectl get rollout <name> -n <namespace> -o jsonpath='{.spec.strategy.blueGreen.scaleDownDelaySeconds}'

# Check ReplicaSet status
kubectl get replicaset -n <namespace> -l app=<app-label> -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,HASH:.metadata.labels.rollouts-pod-template-hash'
```

---

## Version-Specific Notes

### Argo CD v2.14+
- ApplicationSets are first-class (no separate controller install since v2.6, but v2.14 adds progressive sync improvements)
- `argocd.argoproj.io/tracking-method` annotation supports `annotation+label` hybrid
- Multi-source Applications GA — `spec.sources[]` replaces `spec.source`
- Notification triggers moved to `argocd-notifications-cm` ConfigMap
- Application-in-any-namespace feature — Applications can live outside `argocd` namespace when enabled

### Argo Rollouts v1.8+
- `spec.strategy.canary.plugins` for traffic router plugins
- Header-based routing for canary
- Improved Istio multi-cluster support
- `spec.strategy.canary.dynamicStableScale` for optimized replica management
- `spec.analysis.measurementRetention` for keeping measurement history
