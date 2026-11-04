#!/usr/bin/env bash
# Regression tests for catalog-info.yaml checks in check-skill-registration.sh.
# Runs every test inside an isolated copy — never mutates tracked files.
# Requires yq (mikefarah/yq, installed by CI).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v yq >/dev/null 2>&1 || { echo "SKIP: yq not installed (CI installs it)"; exit 0; }

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# Minimal repo copy with what check-skill-registration.sh inspects.
for d in skills scripts .claude-plugin agents assets .github benchmarks; do
  cp -a "$REPO_ROOT/$d" "$SANDBOX/"
done
cp "$REPO_ROOT/Makefile" "$REPO_ROOT/README.md" "$SANDBOX/"
[ -f "$REPO_ROOT/catalog-info.yaml" ] && cp "$REPO_ROOT/catalog-info.yaml" "$SANDBOX/"

cd "$SANDBOX"
SKILL="skills/gitops/argo-knowledge"

passed=0 failed=0
fail() { echo "  FAIL $1"; failed=$((failed+1)); }
pass() { echo "  PASS $1"; passed=$((passed+1)); }
expect_fail() { if bash scripts/check-skill-registration.sh >/dev/null 2>&1; then fail "$1 (expected failure)"; else pass "$1"; fi; }
expect_pass() { if bash scripts/check-skill-registration.sh >/dev/null 2>&1; then pass "$1"; else fail "$1 (expected pass)"; fi; }

# ── 1. Baseline ──────────────────────────────────────────────────────
expect_pass "baseline passes"

# ── 2. Missing catalog-info.yaml ─────────────────────────────────────
cp "$SKILL/catalog-info.yaml" "$SANDBOX/_bak.yaml"
rm "$SKILL/catalog-info.yaml"
expect_fail "detects missing catalog-info.yaml"
cp "$SANDBOX/_bak.yaml" "$SKILL/catalog-info.yaml"

# ── 3. Missing root catalog-info.yaml ────────────────────────────────
mv catalog-info.yaml "$SANDBOX/_root.yaml"
expect_fail "detects missing root catalog-info.yaml"
mv "$SANDBOX/_root.yaml" catalog-info.yaml

# ── 4. Missing target in spec.targets ────────────────────────────────
cp catalog-info.yaml "$SANDBOX/_root2.yaml"
yq -i 'del(.spec.targets[] | select(. == "./'$SKILL'/catalog-info.yaml"))' catalog-info.yaml
expect_fail "detects missing spec.targets entry"
cp "$SANDBOX/_root2.yaml" catalog-info.yaml

# ── 5. Commented target must not satisfy ─────────────────────────────
cp catalog-info.yaml "$SANDBOX/_root3.yaml"
# Move the target outside spec.targets (put it in metadata.description as a string)
yq -i 'del(.spec.targets[] | select(. == "./'$SKILL'/catalog-info.yaml"))' catalog-info.yaml
yq -i '.metadata.description = .metadata.description + " ./'$SKILL'/catalog-info.yaml"' catalog-info.yaml
expect_fail "target outside spec.targets does not satisfy"
cp "$SANDBOX/_root3.yaml" catalog-info.yaml

# ── 6. Description drift beyond first 30 chars ──────────────────────
cp "$SKILL/catalog-info.yaml" "$SANDBOX/_bak2.yaml"
yq -i '.metadata.description = "Knowledge base for Red Hat OpenShift GitOps — TOTALLY DIFFERENT TEXT HERE"' "$SKILL/catalog-info.yaml"
expect_fail "detects late description drift"
cp "$SANDBOX/_bak2.yaml" "$SKILL/catalog-info.yaml"

# ── 7. Empty description in manifest ────────────────────────────────
cp "$SKILL/catalog-info.yaml" "$SANDBOX/_bak3.yaml"
yq -i '.metadata.description = ""' "$SKILL/catalog-info.yaml"
expect_fail "detects empty manifest description"
cp "$SANDBOX/_bak3.yaml" "$SKILL/catalog-info.yaml"

# ── 8. Description at wrong YAML key ────────────────────────────────
cp "$SKILL/catalog-info.yaml" "$SANDBOX/_bak4.yaml"
orig_desc=$(yq -r '.metadata.description' "$SKILL/catalog-info.yaml")
yq -i '.metadata.description = "WRONG" | .metadata.annotations.extra_description = "'"$orig_desc"'"' "$SKILL/catalog-info.yaml"
expect_fail "matching description at wrong key detected as drift"
cp "$SANDBOX/_bak4.yaml" "$SKILL/catalog-info.yaml"

# ── 9. Equivalent YAML formatting (rewrapped, same normalized text) ──
cp "$SKILL/catalog-info.yaml" "$SANDBOX/_bak5.yaml"
# Change from > folded to |- literal block — same text, different YAML style
yq -i '.metadata.description style="literal"' "$SKILL/catalog-info.yaml"
expect_pass "equivalent YAML formatting accepted"
cp "$SANDBOX/_bak5.yaml" "$SKILL/catalog-info.yaml"

# ── 10. Invalid YAML in manifest ─────────────────────────────────────
cp "$SKILL/catalog-info.yaml" "$SANDBOX/_bak6.yaml"
echo "  {{invalid yaml" >> "$SKILL/catalog-info.yaml"
expect_fail "detects invalid YAML"
cp "$SANDBOX/_bak6.yaml" "$SKILL/catalog-info.yaml"

# ── 11. Clean restore ────────────────────────────────────────────────
expect_pass "clean after restore"

echo ""
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
