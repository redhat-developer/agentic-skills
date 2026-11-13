#!/usr/bin/env bash
# Every skill under skills/<product>/<skill>/ must be registered everywhere it needs to
# appear. Adding a skill without wiring it up is how the banner, the Codex manifest, and
# the `make eval` target all silently drifted to a stale 3-4 skill list.
set -euo pipefail

cd "$(dirname "$0")/.."

FAIL=0
note() { printf '  \033[0;31mMISSING\033[0m  %s\n' "$1"; FAIL=1; }

# skills/<product>/<skill>/ — two levels, not one.
SKILL_PATHS=$(find skills -mindepth 2 -maxdepth 2 -type d | sort)

# A guard that inspects nothing must fail rather than report success. When the layout
# moved from skills/<skill>/ to skills/<product>/<skill>/, a one-level find silently
# matched zero skills and every check below was skipped.
if [ -z "$SKILL_PATHS" ]; then
  printf '  \033[0;31mFAIL\033[0m     no skills found under skills/<product>/<skill>/ — nothing was checked.\n'
  exit 1
fi

PRODUCTS=$(echo "$SKILL_PATHS" | cut -d/ -f2 | sort -u)
echo "Products: $(echo "$PRODUCTS" | tr '\n' ' ')"
echo "Skills found: $(echo "$SKILL_PATHS" | sed 's|.*/||' | tr '\n' ' ')"
echo

# Makefile eval targets use a short name. Within a product the skills usually share a
# prefix (argo-knowledge, argo-operations -> knowledge, operations); strip it when every
# skill in that product has it, otherwise use the full name. This keeps existing targets
# working without hardcoding "argo-".
common_prefix_for() {
  local prod="$1" first rest pfx
  first=$(echo "$SKILL_PATHS" | grep "^skills/$prod/" | sed 's|.*/||' | head -1)
  case "$first" in *-*) pfx="${first%%-*}-" ;; *) echo ""; return ;; esac
  for s in $(echo "$SKILL_PATHS" | grep "^skills/$prod/" | sed 's|.*/||'); do
    case "$s" in "$pfx"*) ;; *) echo ""; return ;; esac
  done
  echo "$pfx"
}

for path in $SKILL_PATHS; do
  product=$(echo "$path" | cut -d/ -f2)
  skill=$(echo "$path" | sed 's|.*/||')
  pfx=$(common_prefix_for "$product")
  short="${skill#$pfx}"
  echo "$product/$skill"

  [ -f "$path/SKILL.md" ]              || note "$path/SKILL.md"
  [ -f "$path/evals/evals.json" ]      || note "$path/evals/evals.json"
  [ -f "benchmarks/$skill.md" ]        || note "benchmarks/$skill.md"

  # Compass catalog-info.yaml: existence, root Location target, description match.
  # Uses yq (mikefarah/yq, installed by CI) for reliable YAML parsing.
  manifest="$path/catalog-info.yaml"
  if [ -f "$manifest" ]; then
    # Root Location must exist and list this manifest in spec.targets (not elsewhere).
    if [ ! -f catalog-info.yaml ]; then
      note "root catalog-info.yaml missing"
    else
      if ! yq ".spec.targets[]" catalog-info.yaml 2>/dev/null | grep -qxF "./$manifest"; then
        note "catalog-info.yaml spec.targets missing ./$manifest"
      fi
    fi
    # Full description comparison: yq extracts the value with proper YAML semantics
    # (block scalars, quotes, folding). Normalize whitespace for comparison.
    m_norm=$(yq -r '.metadata.description // ""' "$manifest" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')
    s_norm=$(sed -n '1{/^---$/!q}; 1,/^---$/{/^---$/d; p}' "$path/SKILL.md" | yq -r '.description // ""' 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')
    if [ -z "$m_norm" ]; then
      note "$manifest has missing or empty description"
    elif [ -z "$s_norm" ]; then
      note "$path/SKILL.md has missing or empty description"
    elif [ "$m_norm" != "$s_norm" ]; then
      note "$manifest description does not match SKILL.md"
    fi
  else
    note "$manifest"
  fi

  grep -q "\"./$path\""                .claude-plugin/marketplace.json || note ".claude-plugin/marketplace.json entry for ./$path"
  grep -q "^  - $skill\$"              agents/claude-code/argocd.md    || note "agents/claude-code/argocd.md skills: list"
  grep -q "^eval-$short:"              Makefile                        || note "Makefile target eval-$short"
  grep -qE "^eval:.*[[:space:]]eval-$short([[:space:]]|\$)" Makefile    || note "Makefile 'eval' aggregate does not include eval-$short"
  # The banner shows PRODUCT pills, not one per skill — a per-skill banner would not
  # survive more than a handful of products. Each skill's product must have a pill.
  grep -q ">$product<"                 assets/banner.svg               || note "assets/banner.svg pill for product '$product'"
  grep -q "$skill"                     README.md                       || note "README.md mention"
  grep -qe "^ *- $skill\$"             .github/workflows/evals.yml     || note ".github/workflows/evals.yml choice option"
  grep -qe "^ *- skill: $skill\$"      .github/workflows/evals.yml     || note ".github/workflows/evals.yml matrix entry"
  # agents/codex/argocd.toml was never checked here, and argo-performance-tuning was
  # missing from it from the day it was added — the repo's strongest skill, absent from
  # one runtime, with every other guard green.
  grep -q "skills/$product/$skill/SKILL.md" agents/codex/argocd.toml || note "agents/codex/argocd.toml [[skills.config]] entry"
  grep -q "skills/$product/$skill/SKILL.md" agents/github-copilot/argocd.agent.md || note "agents/github-copilot/argocd.agent.md skill list"
done

# Compass System ↔ plugin coherence (requires yq).
if command -v yq >/dev/null 2>&1; then
  # Both root entities are required when either exists.
  [ -f system.yaml ]                    || note "system.yaml missing"
  [ -f openshift-gitops-plugin.yaml ]   || note "openshift-gitops-plugin.yaml missing"

  if [ -f system.yaml ]; then
    sys_name=$(yq -r '.metadata.name // ""' system.yaml 2>/dev/null)
    [ -n "$sys_name" ] || note "system.yaml metadata.name empty or invalid"
  fi

  if [ -f openshift-gitops-plugin.yaml ]; then
    plugin_system=$(yq -r '.spec.system // ""' openshift-gitops-plugin.yaml 2>/dev/null)
    [ -n "$plugin_system" ] || note "plugin spec.system empty or missing"

    if [ -f system.yaml ] && [ -n "$sys_name" ] && [ -n "$plugin_system" ]; then
      if [ "$plugin_system" != "default/$sys_name" ]; then
        note "plugin spec.system ($plugin_system) does not match system.yaml name (default/$sys_name)"
      fi
    fi

    # Plugin spec.skills must be a YAML sequence of strings listing exactly
    # the discovered skills. A mapping or missing key must not pass.
    skills_kind=$(yq '.spec.skills | type' openshift-gitops-plugin.yaml 2>/dev/null)
    if [ "$skills_kind" != '!!seq' ]; then
      note "plugin spec.skills is not a sequence (got $skills_kind)"
    else
      plugin_skills=$(yq -r '.spec.skills[]' openshift-gitops-plugin.yaml 2>/dev/null | sort)
      expected_skills=""
      for path in $SKILL_PATHS; do
        skill=$(echo "$path" | sed 's|.*/||')
        expected_skills=$(printf '%s\nairesource:ai5-marketplace/%s' "$expected_skills" "$skill")
      done
      expected_skills=$(echo "$expected_skills" | sed '/^$/d' | sort)
      if [ "$plugin_skills" != "$expected_skills" ]; then
        note "plugin spec.skills does not match discovered skills"
      fi
    fi
  fi
fi

# The README badge and the Benchmarks notice cite an eval count. The banner drifted two
# skills behind before anyone noticed; don't let the same happen to a number.
EVAL_TOTAL=$(python3 -c "
import json,glob
print(sum(len(json.load(open(f))['evals']) for f in glob.glob('skills/*/*/evals/evals.json')))")
if ! grep -q "evals-${EVAL_TOTAL}-" README.md; then
  printf '  \033[0;31mSTALE\033[0m    README eval badge does not match the actual total (%s)\n' "$EVAL_TOTAL"
  FAIL=1
fi

echo
if [ "$FAIL" -ne 0 ]; then
  echo "Skill registration check FAILED — see MISSING lines above."
  exit 1
fi
echo "Skill registration check passed — all skills registered everywhere."
