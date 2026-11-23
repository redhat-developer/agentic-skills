#!/usr/bin/env bash
# Regression test for .github/workflows/release.yml packaging logic.
#
# Extracts the ACTUAL "Package skills" run block from the workflow and
# executes it inside an isolated temporary tree.  If the workflow loop
# changes, this test automatically exercises the new code — a
# duplicated loop would silently diverge.
#
# Checks: exact archive count (no extras), >1 members each, tar/zip
# member parity, nontrivial size.  Never touches the repo's own dist/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

WORKFLOW=".github/workflows/release.yml"
[ -f "$WORKFLOW" ] || { echo "FAIL: $WORKFLOW not found"; exit 1; }

# ── Extract the run: block from "Package skills" step ────────────────
SCRIPT=$(awk '
  /- name: Package skills/ { found=1; next }
  found && /run: \|/ { capture=1; next }
  capture {
    if (/^      - name:/ || /^  [^ ]/) exit
    sub(/^          /, "")
    print
  }
' "$WORKFLOW")

[ -n "$SCRIPT" ] || { echo "FAIL: could not extract 'Package skills' from $WORKFLOW"; exit 1; }

# ── Build an isolated sandbox with a COPY of skills/ ─────────────────
# Copying (not symlinking) means cd skills && ../dist stays inside the
# sandbox, and the repo's own dist/ is never created or destroyed.
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

cp -a "$REPO_ROOT/skills" "$SANDBOX/skills"

export TAG=vTEST
(cd "$SANDBOX" && eval "$SCRIPT")

DIST="$SANDBOX/dist"

# ── Collect expected skills (real dirs only, skip symlink products) ───
expected=()
for skill_md in skills/*/*/SKILL.md; do
  dir=$(dirname "$skill_md")
  rel="${dir#skills/}"
  product="${rel%%/*}"
  [ -L "skills/$product" ] && continue
  name="${rel##*/}"
  expected+=("$name")
done

[ ${#expected[@]} -gt 0 ] || { echo "FAIL: no skills found"; exit 1; }

echo "Expected ${#expected[@]} skills: ${expected[*]}"

# ── Assert exact archive counts (no extras) ──────────────────────────
tar_count=$(find "$DIST" -maxdepth 1 -name "*.tar.gz" | wc -l)
zip_count=$(find "$DIST" -maxdepth 1 -name "*.zip" | wc -l)

if [ "$tar_count" -ne "${#expected[@]}" ] || [ "$zip_count" -ne "${#expected[@]}" ]; then
  echo "FAIL: expected ${#expected[@]} tar.gz + ${#expected[@]} zip, got $tar_count tar.gz + $zip_count zip"
  ls "$DIST"
  exit 1
fi

# ── Verify each skill archive ────────────────────────────────────────
passed=0
failed=0
fail() { echo "  FAIL $1"; failed=$((failed+1)); }
pass() { echo "  PASS $1"; passed=$((passed+1)); }

for name in "${expected[@]}"; do
  tgz="$DIST/${name}-${TAG}.tar.gz"
  zipf="$DIST/${name}-${TAG}.zip"

  [ -f "$tgz" ] || { fail "$name tar.gz missing"; continue; }
  [ -f "$zipf" ] || { fail "$name zip missing"; continue; }

  tgz_size=$(stat -c%s "$tgz" 2>/dev/null || stat -f%z "$tgz")
  zip_size=$(stat -c%s "$zipf" 2>/dev/null || stat -f%z "$zipf")
  [ "$tgz_size" -gt 100 ] || { fail "$name tar.gz too small ($tgz_size bytes)"; continue; }
  [ "$zip_size" -gt 100 ] || { fail "$name zip too small ($zip_size bytes)"; continue; }

  tar_members=$(tar tzf "$tgz" | sed 's|/$||' | sort)
  zip_members=$(zipinfo -1 "$zipf" | sed 's|/$||' | sort)
  member_count=$(echo "$tar_members" | wc -l)

  [ "$member_count" -gt 1 ] || { fail "$name only $member_count member (need >1)"; continue; }

  if [ "$tar_members" = "$zip_members" ]; then
    pass "$name ($member_count members, tar=${tgz_size}B zip=${zip_size}B)"
  else
    fail "$name member mismatch"
    diff <(echo "$tar_members") <(echo "$zip_members") || true
  fi
done

echo ""
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
