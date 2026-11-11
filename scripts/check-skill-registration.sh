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
