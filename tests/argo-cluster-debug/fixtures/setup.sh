#!/usr/bin/env bash
# Deploy the argo-cluster-debug eval fixtures to a live cluster, and arm their
# symptoms. Teardown: ./teardown.sh
#
# Why this exists: several argo-cluster-debug evals name resources that do not
# exist on a stock cluster, so both the skill and the baseline arm get capped at
# `partial` on every expectation that needs a real finding — the suite cannot
# measure what it claims to. These fixtures create the real conditions.
#
# WRITES TO THE CLUSTER. Everything carries argo-skills-eval-fixture=true and is
# removed by teardown.sh. Do not run against a cluster you care about.
#
#   eval 1  podinfo          OutOfSync AND Degraded   (live image drift, selfHeal off)
#   eval 2  frontend         canary parked at step 2  (analysis-driven pause)
#   eval 4  team-apps        generates 0 Applications (path pattern matches nothing)
#   eval 5  eval-rollingsync RollingSync, staging unhealthy (see the note at the end)
#   eval 6  checkout-api     blue-green held at preview (autoPromotionEnabled false)
#   eval 8  billing-service  health Suspended         (paused blue-green Rollout)
#   eval 9  platform-ui      ComparisonError          (multi-source, bad $values path)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KCTL="$(command -v oc >/dev/null 2>&1 && echo oc || echo kubectl)"
NS_ARGOCD="${NS_ARGOCD:-openshift-gitops}"

# ---------------------------------------------------------------------------
# Refuse to adopt namespaces we did not create.
#
# Two of these are called `production` and `prod` because that is what the eval
# prompts say. If either already exists and is not ours, this script must not
# touch it and teardown must not delete it — so stop here rather than discover
# that at teardown time.
# ---------------------------------------------------------------------------
echo "==> checking namespace ownership"
conflict=0
for ns in apps finance eval-staging eval-production production prod; do
  if $KCTL get ns "$ns" >/dev/null 2>&1; then
    if [ "$($KCTL get ns "$ns" -o jsonpath='{.metadata.labels.argo-skills-eval-fixture}' 2>/dev/null)" = "true" ]; then
      echo "    $ns — exists, ours (left over from a previous run)"
    else
      echo "    $ns — EXISTS AND IS NOT OURS"
      conflict=1
    fi
  fi
done
if [ "$conflict" -ne 0 ]; then
  echo
  echo "Refusing to run. One or more fixture namespaces already exist without the"
  echo "argo-skills-eval-fixture=true label, so they belong to someone else. Adopting"
  echo "them would mean teardown.sh deletes a namespace this suite did not create."
  echo "Rename the fixture namespaces in manifests.yaml, or clear the conflict first."
  exit 1
fi

echo "==> creating namespaces first"
# The namespaces have to exist before anything else can be server-dry-run: this
# file contains Rollouts, Services and an AnalysisTemplate that live in them, and
# `--dry-run=server` resolves the namespace for real. Applying the whole file in
# one pass fails with "namespaces \"production\" not found" even though the
# Namespace object is right there in the same document.
awk 'BEGIN{RS="---\n"} /\nkind: Namespace\n/ {print "---"; print}' \
  "$HERE/manifests.yaml" | $KCTL apply -f -
for ns in apps finance eval-staging eval-production production prod; do
  for _ in $(seq 1 12); do
    [ "$($KCTL get ns "$ns" -o jsonpath='{.status.phase}' 2>/dev/null)" = "Active" ] && break
    sleep 2
  done
done

echo "==> applying manifests (server dry-run first)"
$KCTL apply -f "$HERE/manifests.yaml" --dry-run=server --validate=strict >/dev/null
$KCTL apply -f "$HERE/manifests.yaml"

echo "==> waiting for the initial sync"
for _ in $(seq 1 30); do
  ready=$($KCTL get applications.argoproj.io -n "$NS_ARGOCD" \
            -o jsonpath='{range .items[*]}{.metadata.name}={.status.sync.status}{"\n"}{end}' 2>/dev/null \
          | grep -c '=Synced' || true)
  [ "${ready:-0}" -ge 3 ] && break
  sleep 10
done

echo "==> arming eval 1: drift podinfo's live image so it is OutOfSync AND Degraded"
# One action produces both symptoms: the live spec diverges from git (OutOfSync)
# and the tag is unpullable (ImagePullBackOff -> Degraded).
#
# Disable automated sync FIRST. An earlier version relied on `selfHeal: false` alone
# and that is not sufficient: with `automated` still set, Argo CD re-synced and put
# the good image back within ~30 seconds, leaving podinfo Synced/Healthy. Eval 1 then
# measured nothing — the exact failure this whole fixture file exists to prevent, and
# it is silent, because the script completes and the Application looks fine.
$KCTL patch applications.argoproj.io podinfo -n "$NS_ARGOCD" --type=json \
  -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]' 2>/dev/null \
  || echo "    (automated sync already absent)"

dep=$($KCTL get deploy -n apps -o jsonpath='{.items[0].metadata.name}')
container=$($KCTL get deploy "$dep" -n apps -o jsonpath='{.spec.template.spec.containers[0].name}')
$KCTL set image -n apps "deploy/$dep" \
  "$container=registry.access.redhat.com/ubi8/nonexistent-eval:9.9.9"
# Default progressDeadlineSeconds is 600; shorten it so Degraded appears in ~1min
# rather than 10. Without this the eval sees Progressing, not Degraded.
$KCTL patch deploy "$dep" -n apps --type=merge -p '{"spec":{"progressDeadlineSeconds":60}}'

echo "==> arming eval 8: pause the blue-green Rollout so health reports Suspended"
ro=$($KCTL get rollout -n finance -o jsonpath='{.items[0].metadata.name}')
$KCTL patch rollout "$ro" -n finance --type=merge -p '{"spec":{"paused":true}}'

echo "==> arming eval 9: hard-refresh platform-ui so the ComparisonError is populated"
# The manifest-generation error is cached by repo-server; a soft refresh will not
# surface it. Note the FULL resource name: on a cluster running Open Cluster
# Management, `get application` resolves to applications.app.k8s.io instead.
$KCTL annotate applications.argoproj.io platform-ui -n "$NS_ARGOCD" \
  argocd.argoproj.io/refresh=hard --overwrite >/dev/null

# ---------------------------------------------------------------------------
# Evals 2 and 6 need a SECOND revision.
#
# Argo Rollouts does not run the canary steps or create a preview ReplicaSet on
# the very first rollout of a Rollout object — the initial deploy goes straight
# to the active/stable state. So both of these only reach the state their prompt
# describes after an update. Without this the fixtures deploy Healthy and the
# evals measure nothing, which is the failure mode they were written to fix.
# ---------------------------------------------------------------------------
echo "==> waiting for the baseline revision of the new Rollouts to go Healthy"
for ns_ro in production/frontend prod/checkout-api; do
  ns="${ns_ro%%/*}"; name="${ns_ro##*/}"
  for _ in $(seq 1 30); do
    [ "$($KCTL get rollout "$name" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null)" = "Healthy" ] && break
    sleep 10
  done
  echo "    $ns_ro -> $($KCTL get rollout "$name" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null)"
done

echo "==> arming eval 2: trigger revision 2 so the canary enters step 1 then parks at step 2"
# steps[0] setWeight:20 completes immediately; steps[1] starts the AnalysisRun,
# whose Job sleeps, so the Rollout sits at step index 1 — the user's "step 2".
# Bump an env var, NOT the image. Any pod-template change triggers a new revision,
# and an env change is guaranteed to produce pods that actually start. An earlier
# version bumped the image tag instead and picked one that does not exist, so the
# canary pod sat in ImagePullBackOff and the Rollout never left step 0 — it never
# reached the analysis step the eval is about.
#
# --type=json, not --type=merge. A JSON merge patch REPLACES an array rather than
# merging into it, so patching `containers` that way drops every field not restated
# — including `image`, which left the Rollout Degraded with
# "spec.template.spec.containers[0].image: Required value". Strategic merge patch
# would merge by container name, but Kubernetes does not support it on CRDs, and a
# Rollout is a CRD.
$KCTL patch rollout frontend -n production --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/env","value":[{"name":"REVISION","value":"2"}]}]'

echo "==> arming eval 6: trigger revision 2 so blue-green holds at preview"
# autoPromotionEnabled: false means the new ReplicaSet is brought up behind the
# preview Service and waits for a manual promotion that never comes.
$KCTL patch rollout checkout-api -n prod --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/env","value":[{"name":"REVISION","value":"2"}]}]'

echo "==> settling"
sleep 120

echo
echo "==> state"
echo "--- Applications (expect: podinfo OutOfSync/Degraded, billing-service Suspended,"
echo "                 platform-ui Unknown with a ComparisonError) ---"
$KCTL get applications.argoproj.io -A \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' --no-headers

echo "--- Rollouts (expect: frontend Paused at step 1, checkout-api Paused) ---"
$KCTL get rollouts.argoproj.io -A -l argo-skills-eval-fixture=true \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,STEP:.status.currentStepIndex,MSG:.status.message' --no-headers

echo "--- AnalysisRuns for eval 2 (expect: one Running) ---"
$KCTL get analysisruns.argoproj.io -n production --no-headers 2>/dev/null || echo "    none"

echo "--- ApplicationSet team-apps (expect: 0 generated Applications) ---"
$KCTL get applications.argoproj.io -n "$NS_ARGOCD" -l argo-skills-eval-fixture=true \
  --no-headers 2>/dev/null | grep -c '^team-' || echo "    0 generated (as intended)"

echo
echo "NOTE on eval 5: RollingSync is declared on the ApplicationSet but is INERT on"
echo "OpenShift GitOps unless the applicationset controller runs with"
echo "--enable-progressive-syncs, which the operator does not set by default. Enabling"
echo "it means editing the shared ArgoCD CR, so this script deliberately does not."
echo "Eval 5 therefore still measures the inert case — which is itself the realistic"
echo "OpenShift GitOps failure mode, and what the skill documents."

# ---------------------------------------------------------------------------
# Verify the fixtures actually reached the states the evals assert.
#
# Printing a state table is not the same as checking it. A fixture that failed
# to arm leaves the eval measuring a healthy resource, both arms score the same,
# and the run looks successful — so this exits non-zero instead, loudly.
#
# Known flake: something restores the podinfo deployment image within ~15s while
# other agents are working the cluster. Argo auto-sync, agent writes and the
# other fixture Applications have all been ruled out and the mechanism is still
# unidentified. Do not arm fixtures while an eval run is in flight, and re-run
# this script if the check below fails.
# ---------------------------------------------------------------------------
echo
echo "==> verifying fixture states"
fail=0
check() {  # check <description> <actual> <expected>
  if [ "$2" = "$3" ]; then
    echo "    [OK]   $1 = $3"
  else
    echo "    [FAIL] $1 = '${2:-<empty>}', expected '$3'"
    fail=1
  fi
}
app_health() { $KCTL get applications.argoproj.io "$1" -n "$NS_ARGOCD" -o jsonpath='{.status.health.status}' 2>/dev/null; }
app_sync()   { $KCTL get applications.argoproj.io "$1" -n "$NS_ARGOCD" -o jsonpath='{.status.sync.status}'   2>/dev/null; }

check "eval 1  podinfo sync"            "$(app_sync podinfo)"          "OutOfSync"
check "eval 1  podinfo health"          "$(app_health podinfo)"        "Degraded"
check "eval 8  billing-service health"  "$(app_health billing-service)" "Suspended"
check "eval 9  platform-ui sync"        "$(app_sync platform-ui)"      "Unknown"
check "eval 6  checkout-api phase"      "$($KCTL get rollout checkout-api -n prod -o jsonpath='{.status.phase}' 2>/dev/null)" "Paused"

if [ "$fail" -ne 0 ]; then
  echo
  echo "FIXTURES NOT ARMED. Do not run the evals against this cluster — the affected"
  echo "evals would measure a resource in the wrong state and report a meaningless"
  echo "score. Re-run this script with nothing else touching the cluster."
  exit 1
fi
echo "    all fixture states verified"
