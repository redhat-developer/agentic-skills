# Write safety protocol

**Shared protocol, not a skill.** Imported by `argo-cluster-debug` and
`argo-performance-tuning`. It is a file rather than a directory on purpose: every skill
enumerator in this repo matches `skills/<product>/<skill>/` as a *directory*
(`scripts/check-skill-registration.sh`, `ci.yml`, `release.yml`), so a directory here
would be treated as an unregistered skill and fail CI.

**Every write follows: Generate → Preview → Blast radius → Confirm → Verify.** Preview
shows what changes on the object; blast radius shows who else is affected. Those are
different questions and a diff only answers the first.

The verify step is not optional. A benchmark run found a skill losing to an unaided
baseline on exactly one thing: it stopped at the confirmation gate and never checked the
change worked. Applying without verifying is how a "successful" change is discovered to
be broken hours later.

**Read-only work** — diagnosis, status checks, version queries, audits — does NOT require
confirmation. Execute and report. This protocol governs only operations that modify
cluster state.

> **Scope note.** Authoring desired state (Applications, ApplicationSets, AppProjects,
> notification config) is out of scope for every skill in this repo: it belongs in Git,
> where Argo CD reconciles it. If a request asks you to apply desired state directly,
> say why that produces the drift Argo CD exists to prevent, and hand back the manifest
> to commit. This protocol covers runtime state no controller owns — Rollout promotion,
> aborts, retries — and tuning changes to operator-managed config.

## Step 1: Generate

Produce the manifest or command. Show it in a fenced code block. Execute nothing yet.

## Step 2: Preview

| Operation | Preview with |
|---|---|
| Update operator-managed config (`ArgoCD` CR) | `kubectl diff -f <file>` or `oc diff -f <file>` |
| Create a resource | `kubectl apply --dry-run=server --validate=strict -f <file> -o yaml` |
| Promote / abort / retry a Rollout | `kubectl argo rollouts status <name> -n <ns>` — show current state first |
| Delete a resource | `kubectl get <kind> <name> -n <ns>` — show what exists |

Show the output. Explain what will change in plain language.

### `--dry-run=client` is a weak preview — do not rely on it

It renders the file locally. It contacts no admission or schema validation and does not
merge against live state, so **for an update it cannot show what will change** — it
echoes your input back. Measured against a real cluster:

```
manifest with a nonexistent field AND a wrong-typed value
  kubectl apply --dry-run=client                     -> ACCEPTED   (no validation at all)
  kubectl apply --dry-run=server --validate=strict   -> REJECTED   (schema validated)
```

- **Creating?** `--dry-run=server --validate=strict`. Fall back to client only if the API
  rejects a server dry-run outright (CRD absent), and say plainly nothing was validated.
- **Updating?** `kubectl diff`. A client dry-run is never a preview of an update;
  presenting one as the Preview step gives false assurance the change is understood.

## Step 2b: Blast radius — who else does this touch?

A diff answers "what changes on **this object**". It does not answer "what **else** is
affected", and for Argo CD those are rarely the same question: most of its objects are
fan-out points. A one-field diff on an `ArgoCD` CR looks trivial and restarts components
every Application on the instance depends on.

Compute it, and show the result before asking to confirm:

```bash
<repo-root>/scripts/blast-radius.sh <kind> <name> [namespace]
```

Handles `ArgoCD`, `AppProject`, `ApplicationSet`, `Application`, `RolloutManager` and the
shared ConfigMaps; strictly read-only. **Exit 3 means no cluster was reachable** — reason
the impact out from the manifests instead and say it was not verified. **Exit 4 means a
lookup failed**, so the radius is UNKNOWN rather than zero; never read it as "nothing is
affected".

Say the number out loud. "This restarts the repo-server serving 47 Applications" lands
differently from "this changes one field". An empty result is worth stating too: "blast
radius: just this Application, nothing else references it".

This applies to **recommendations as well as writes.** If you tell the user to do
something you are not executing, it still needs its impact stated. Most of the harm from
a bad recommendation happens after the session ends.

## Step 3: Confirm

Ask explicitly: **"Apply this? (yes/no)"**

Do not proceed without an affirmative. Acceptable: "yes", "y", "apply", "do it", "go
ahead", "ship it". Anything else is a no.

**For destructive operations (delete, prune, rollback), require the user to type the
resource name.** "yes" alone is not sufficient. Ask: *"Type the resource name `<name>` to
confirm deletion."*

## Step 4: Verify

**After every applied change, check it took effect and show the output.** An apply
returning `configured` means the API accepted the object — not that the operator
reconciled it, the pods rolled, or the thing you wanted is true.

| Operation | Verify with |
|---|---|
| Operator-managed change (`ArgoCD` CR) | `$KCTL get argocd <name> -n "$NS" -o jsonpath='{.status}'`, then confirm the affected pods restarted: `$KCTL get pods -n "$NS"` |
| Any field you set | `$KCTL get <kind> <name> -n "$NS" -o yaml` — confirm it is actually present; the operator may reconcile it away |
| Promote / abort / retry a Rollout | `kubectl argo rollouts get rollout <name> -n <ns>` — report the **resulting phase**, not that the command returned |
| Delete | confirm it is gone *and* that nothing unintended went with it (cascading finalizer deletions) |

Rules:

1. **Report the verification output.** "Applied and verified" with no command output is
   not a verification.
2. **Allow for reconciliation lag.** Operator- and Argo-managed changes are not instant.
   If the first check does not show the expected state, say so and re-check rather than
   declaring success or failure.
3. **If verification fails, say so plainly** and do not auto-remediate. Report observed
   versus expected and let the user decide.
4. **If the operation could not be executed, still state the verification plan.** Missing
   tool, absent resource, unreachable cluster, or stopping at the confirmation gate —
   name the checks you *would* run and what each should show. Dropping verification
   because nothing was applied is the most common way this step gets skipped, and it
   leaves the user unable to tell afterwards whether it worked.

## Hard constraints

Violating any of these is a blocker.

1. **NEVER apply without showing what will change first.** No silent writes.
2. **NEVER delete without listing what will be removed** — kind, name, namespace, age.
3. **NEVER force anything without an explicit request.** If the user says "abort", abort
   normally; use `--force` only if they said "force".
4. **Destructive operations require the typed resource name** (see Step 3).
5. **Log every applied change, then verify it:**
   `[APPLIED] <timestamp> <kind>/<namespace>/<name> — <action>`
   followed by the Step 4 output. An `[APPLIED]` line alone is a claim, not evidence.
6. **If a command fails, show the error and suggest recovery.** Do not retry
   automatically.
7. **NEVER run `kubectl delete --all` or `kubectl delete ns`** without explicit
   confirmation of the namespace name and a list of what will be destroyed.
8. **NEVER modify Secrets containing credentials directly.** Credential material belongs
   in a secrets manager — External Secrets Operator, Vault, Sealed Secrets — not in an
   ad-hoc agent write.

## Destructive operations checklist

- [ ] Current cluster context is correct (`kubectl config current-context`)
- [ ] Target namespace is correct
- [ ] The resource exists and is the right one
- [ ] The user has explicitly confirmed by typing the resource name
