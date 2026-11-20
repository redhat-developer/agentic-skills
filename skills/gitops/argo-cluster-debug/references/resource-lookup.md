# When the named resource does not exist

The most common real debugging session does not start from a broken resource — it starts
from a name that does not resolve. Typo, wrong namespace, wrong cluster context, wrong
Argo CD instance, or already deleted. **Establish this before running any workflow**, or
you will produce a confident analysis of nothing.

```bash
# 1. Search cluster-wide. Always the FULL resource name — see the gotcha below.
$KCTL get applications.argoproj.io -A | grep -i <name>

# 2. Not there? It may have been deleted recently.
$KCTL get events -A --field-selector involvedObject.name=<name> \
  --sort-by=.lastTimestamp 2>/dev/null | tail -5

# 3. Confirm you are on the cluster the user means.
$KCTL config current-context

# 4. Confirm which Argo CD instance should own it.
$KCTL get argocd -A
```

**Gotcha — the short form can resolve to the wrong CRD.** On clusters running Open
Cluster Management (common on OpenShift), `kubectl get application <name>` resolves to
`applications.app.k8s.io`, not Argo CD, and returns a `NotFound` for the *wrong kind*:

```
Error from server (NotFound): applications.app.k8s.io "<name>" not found
```

That reads as "your Application is gone" when it may exist perfectly well. Always write
`applications.argoproj.io` explicitly.

**This is not limited to `application`.** Any short name served by more than one API
group resolves to whichever group sorts first, and a miss is reported as `NotFound` for
that *other* kind — which reads as "it does not exist" rather than "you asked the wrong
API". On a cluster running ACM/MCE, `subscription` is the other common one:

```bash
# Two groups serve `subscriptions` on an ACM cluster:
#   apps.open-cluster-management.io/v1   <- the bare name hits this
#   operators.coreos.com/v1alpha1        <- OLM's, the one you almost always want
$KCTL get subscription -A                        # "No resources found"  (WRONG kind)
$KCTL get subscriptions.operators.coreos.com -A  # the operator Subscriptions
```

Observed: a bare `get subscription -A` returned "No resources found" on a cluster whose
OLM Subscription was present and healthy, which led to a confident — and wrong — root
cause of "the Subscription was deleted".

**Before trusting any empty result, check whether the short name is ambiguous:**

```bash
$KCTL api-resources | awk '$1=="<shortname>"'   # more than one row == ambiguous
```

An empty result from a bare short name is not evidence of absence.

**Then report it as a finding, not a failure.** State what you searched and what exists.
If you demonstrate the method on a different resource, say so in the heading — never let
a substitute read as the user's resource.

