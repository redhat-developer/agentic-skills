#!/usr/bin/env bash
# Remove everything setup.sh created, and verify nothing is left behind.
set -euo pipefail

KCTL="$(command -v oc >/dev/null 2>&1 && echo oc || echo kubectl)"
NS_ARGOCD="${NS_ARGOCD:-openshift-gitops}"
LABEL="argo-skills-eval-fixture=true"

# Two of these are named `production` and `prod` because that is what the eval
# prompts say. Deleting a namespace by name alone would therefore be a loaded
# gun on a shared cluster: if someone else already owns `prod`, a teardown here
# would take it with us. Nothing below deletes a namespace it cannot first prove
# carries our fixture label. setup.sh refuses to adopt a pre-existing namespace
# for the same reason, so the label is only ever on namespaces we made.
NAMESPACES=(apps finance eval-catalog eval-crashloop eval-pending eval-project-deny eval-healthy \
            eval-staging eval-production production prod)

owned() {  # owned <ns> -> true if the namespace exists AND is ours
  [ "$($KCTL get ns "$1" -o jsonpath='{.metadata.labels.argo-skills-eval-fixture}' \
       2>/dev/null)" = "true" ]
}

echo "==> deleting fixture Applications, ApplicationSets, AppProjects and Rollouts"
# Delete the Argo CD objects first: removing the namespaces while an Application
# still manages them leaves the Application reconciling against a terminating
# namespace, which can hang the delete.
$KCTL delete applicationset,applications.argoproj.io -n "$NS_ARGOCD" -l "$LABEL" --ignore-not-found
# AppProjects after Applications so nothing still references eval-locked mid-delete.
$KCTL delete appprojects.argoproj.io -n "$NS_ARGOCD" -l "$LABEL" --ignore-not-found
for ns in "${NAMESPACES[@]}"; do
  owned "$ns" || continue
  $KCTL delete rollouts.argoproj.io,analysistemplates.argoproj.io,analysisruns.argoproj.io \
    -n "$ns" -l "$LABEL" --ignore-not-found 2>/dev/null || true
done
sleep 20

echo "==> deleting fixture namespaces"
skipped=()
for ns in "${NAMESPACES[@]}"; do
  if owned "$ns"; then
    $KCTL delete ns "$ns" --ignore-not-found --wait=false
  elif $KCTL get ns "$ns" >/dev/null 2>&1; then
    skipped+=("$ns")
  fi
done

if [ ${#skipped[@]} -gt 0 ]; then
  echo
  echo "  NOT DELETING (exists but is not labelled $LABEL — not ours):"
  printf '    %s\n' "${skipped[@]}"
fi

for _ in $(seq 1 18); do
  left=0
  for ns in "${NAMESPACES[@]}"; do
    owned "$ns" && left=$((left+1))
  done
  [ "$left" -eq 0 ] && break
  sleep 10
done

echo
echo "==> verification"
fail=0
for ns in "${NAMESPACES[@]}"; do
  if owned "$ns"; then
    echo "  STILL PRESENT: namespace/$ns ($($KCTL get ns "$ns" -o jsonpath='{.status.phase}'))"; fail=1
  fi
done
remaining=$($KCTL get applications.argoproj.io,applicationsets.argoproj.io,appprojects.argoproj.io -A -l "$LABEL" \
            --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "$remaining" != "0" ] && { echo "  STILL PRESENT: $remaining labelled Argo object(s)"; fail=1; }
rollouts=$($KCTL get rollouts.argoproj.io -A -l "$LABEL" --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "$rollouts" != "0" ] && { echo "  STILL PRESENT: $rollouts labelled Rollout(s)"; fail=1; }

if [ "$fail" -eq 0 ]; then
  echo "  clean — no fixture namespaces, no labelled Argo objects"
  echo
  echo "  remaining Applications on the cluster (should be yours only):"
  $KCTL get applications.argoproj.io -A --no-headers 2>/dev/null | sed 's/^/    /'
else
  echo
  echo "  teardown INCOMPLETE — investigate before leaving the cluster."
  exit 1
fi
