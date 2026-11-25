<!-- Loaded on demand by app-sync-triage.md when the status is
     Synced but the cluster does not match expectations. Read-only. -->

# Synced but wrong

The Application reports `Synced` and the cluster is not what git says. `Synced` is not
a claim that the cluster matches the repository — it is a claim that **the comparison
Argo CD performed found no difference**. Those differ whenever the comparison is
looking at the wrong thing, a narrower thing, or stale data.

This is the mirror of `Unknown` in health triage: the status is reassuring and wrong,
so nobody investigates. Work down the list; the causes are ordered by how often they
are the answer.

## 1. Is the comparison fresh?

A `Synced` from twenty minutes ago says nothing about now.

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath=''\
'reconciledAt={.status.reconciledAt}{"\n"}'\
'syncedRevision={.status.sync.revision}{"\n"}'\
'targetRevision={.spec.source.targetRevision}{"\n"}'\
'revisions={.status.sync.revisions}{"\n"}'\
'{range .spec.sources[*]}repo={.repoURL} target={.targetRevision} path={.path} chart={.chart} ref={.ref}{"\n"}{end}'
date -u +%Y-%m-%dT%H:%M:%SZ
```

Check effective polling and webhook policy before diagnosing an old comparison. In
3.4 the defaults are 120s plus up to 60s jitter; custom intervals and disabled polling
are supported. Use `sync-outofsync.md` section 4 for freshness/revision checks, reusing
the source-index/revision mapping for multi-source Applications.

Then confirm the synced revision is the commit you expect. The most common version of
"Synced but wrong" is simply that `status.sync.revision` is an older commit than the
branch head, which makes `Synced` entirely accurate and the expectation wrong.
`sync-outofsync.md` section 4 covers revision resolution.

## 2. Is Argo CD looking at the object you are looking at?

Check the configured tracking method and resource identity, but do not assume a
tracking failure from the Application status alone. An object absent from the managed
resource list might be outside the rendered source, excluded, or looked up in a
different namespace/cluster; section 4 checks those possibilities.

```bash
$KCTL get cm argocd-cm -n "$NS" -o jsonpath='{.data.application\.resourceTrackingMethod}{"\n"}'

$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='{range .status.resources[*]}{.kind}/{.namespace}/{.name}{"\n"}{end}'
```

If the object is not in that list, establish why it is outside the current comparison.
A repository file is not proof that the source rendered it. Check what the live object
is tagged with and compare its group/kind/namespace/name with the rendered manifest:

```bash
$KCTL get <kind> <name> -n <ns> -o jsonpath=''\
'instance={.metadata.labels.app\.kubernetes\.io/instance}{"\n"}'\
'trackingId={.metadata.annotations.argocd\.argoproj\.io/tracking-id}{"\n"}'
```

| Method | Key | Failure mode |
|---|---|---|
| `label` (legacy or explicit opt-out in 3.x) | `app.kubernetes.io/instance` | 63-character value limit; chart-written labels can conflict with ownership tracking. |
| `annotation` (default in 3.x) | `argocd.argoproj.io/tracking-id` | Verify the Application and resource identity encoded in the annotation. |
| `annotation+label` | both | The label is written for compatibility; the annotation is authoritative. |

Investigate Helm label collisions or truncation only when label tracking is active.
Under annotation tracking, a differing Helm instance label alone does not detach the
resource. Neither a missing tag nor absence from `status.resources` proves a duplicate
will be created: verify rendered identity and scope before attributing the mismatch.

On an operator-managed instance the tracking method is `.spec.resourceTrackingMethod`
on the `ArgoCD` CR. An `argocd-cm` edit is reverted.

Source: [Argo CD 3.0 tracking migration](https://argo-cd.readthedocs.io/en/release-3.4/operator-manual/upgrading/2.14-3.0/#use-annotation-based-tracking-by-default).

## 3. Is the difference being ignored on purpose?

`ignoreDifferences` suppresses a real difference from the diff. The field genuinely
does not match and the Application genuinely reports `Synced`.

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='{.spec.ignoreDifferences}{"\n"}'

# Example implicated kind; adapt to the resource and inspect legacy/wildcard entries if used.
$KCTL get cm argocd-cm -n "$NS" \
  -o jsonpath='{.data.resource\.customizations\.ignoreDifferences\.apps_Deployment}{"\n"}'
```

Also check the annotations on the resource itself:

| Annotation | Effect |
|---|---|
| `argocd.argoproj.io/compare-options: IgnoreExtraneous` | An extraneous live resource does not make the Application OutOfSync. This does not suppress field differences on a desired resource, remove its health assessment, or disable pruning. |
| `argocd.argoproj.io/sync-options: Prune=false` | Kept, but still compared. |

A system-level `ignoreDifferences` in `argocd-cm` applies to every Application on the
instance, so this cause can be invisible from the Application spec alone. Check both
places before concluding there is no suppression.

Source: [Argo CD 3.4 compare options](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/compare-options/).

## 4. Is the resource managed at all?

Distinguish never-managed objects from tracked live-only resources: the latter can
be extraneous/prune candidates and contribute to OutOfSync. Check rendered source,
tracking identity, exclusions and compare options before declaring an object out of scope.

Causes that silently drop a resource from the desired state:

- A Helm conditional or `.Values` toggle that evaluates false, so the template emits
  nothing.
- A Kustomize `resources:` list that does not include the file. An orphaned file in the
  directory is never rendered.
- A path change, where the Application still points at the old `spec.source.path`.
- A `resource.exclusions` entry in `argocd-cm` or `.spec.resourceExclusions` on the CR.
  Match its API groups, kinds and cluster URL patterns against the actual destination.

```bash
$KCTL get cm argocd-cm -n "$NS" -o jsonpath='{.data.resource\.exclusions}{"\n"}'
```

Exclusions are configured at instance scope, but a rule can select particular clusters.
Only matching kinds on matching destinations are excluded; do not infer that every
Application on the instance is affected.

## 5. Did someone change the cluster directly?

If the object differs from git and Argo CD reports `Synced`, and sections 1 to 4 are
clear, the live change is in a field the comparison does not reach.

```bash
$KCTL get <kind> <name> -n <ns> -o jsonpath='<specific differing fields>'
$KCTL get events -n <ns> --field-selector involvedObject.name=<name> --sort-by=.lastTimestamp | tail -10
```

Reuse the effective automation policy (`../SKILL.md`). `selfHeal: true` does not
cause reversion when `automated.enabled: false`; and an ignored difference may not
trigger self-heal at all. Correlate an actual controller operation before attributing
a live edit's disappearance to Argo CD. Durable intended changes still belong in Git.

## 6. Report

Say plainly that the status is accurate but not answering the question the user asked,
and name which layer hid the difference: a stale comparison, a tracking mismatch, a
suppressed field, a resource outside the render, or a field nobody is comparing.

Give the evidence as a pair — what git specifies, and what the live object contains —
rather than describing the mismatch. A diagnosis of this symptom is not believable
without both halves side by side.
