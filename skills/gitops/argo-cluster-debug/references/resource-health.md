# Read per-resource health

Load before any health leaf filters resources by health. Reuse a successful current-run
snapshot rather than fetching it again at every handoff. Set the CLI, instance namespace
and Application name/object namespace in every shell call that uses them.

## 1. Establish where health is stored

In Argo CD 3.x, per-resource health is normally stored in the application tree rather
than `.status.resources[].health` in the Kubernetes Application CR. Aggregate
`.status.health` and per-resource sync status are still available in the CR.

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='source={.status.resourceHealthSource}{"\n"}health={.status.health}{"\n"}reconciledAt={.status.reconciledAt}{"\n"}resources={.status.resources}{"\n"}'
```

`resourceHealthSource: appTree` means the tree is required. `inline` means the
controller persisted per-resource health. The setting `controller.resource.health.persist=true`
enables inline persistence. Inspect effective controller configuration only when
the source and observed output disagree. Read only the
`controller.resource.health.persist` key in `argocd-cmd-params-cm` when needed to
resolve that discrepancy; it is not a prerequisite when the source is established.
An absent flag or denied ConfigMap read is not proof that persistence is enabled. Do not enable it during diagnosis.

An empty health field can also mean that a kind has no health assessment. Never turn
an absent value into `Healthy`, `Unknown`, or an unhealthy finding. In particular,
`grep -v Healthy` on incomplete CR rows manufactures findings.

## 2. Collect the resource snapshot

When populated inline, reuse the complete resource list above. It omits Application
annotations and spec values while preserving resource identities, sync and health.
Do not repeat the fetch solely to change output format.

When health is external or incomplete, use an authenticated CLI against the owning
Argo CD server, without `--refresh` or `--hard-refresh`:

```bash
# Preserve command failures rather than treating empty/invalid output as no findings.
set -o pipefail
argocd app get "$APP" --app-namespace "$APP_NS" -o json | python3 -c '
import json, sys
app = json.load(sys.stdin)
status = app.get("status", {})
print(json.dumps({"health": status.get("health"), "reconciledAt": status.get("reconciledAt"), "resourceHealthSource": status.get("resourceHealthSource"), "resources": status.get("resources")}))'
```

This projection requires Python 3; an existing runtime JSON filter is an alternative.
The CLI retrieves tree health for the Application. Preserve resource identity
(group/kind/namespace/name), health status/message, and sync status. If using the
runtime's existing authenticated API client instead, the read-only endpoint is:

```text
GET /api/v1/applications/{applicationName}/resource-tree?appNamespace={applicationNamespace}
```

Read `nodes[].health` and join by resource identity to the Application's resource
list; the tree includes descendants that do not themselves drive Application rollup.
Do not substitute `argocd app list`, which omits individual resource health.

If CLI/API access is absent or denied, inspect accessible live objects and their
conditions, pods and events using the resource identities in the CR. Report that
Argo CD's per-resource assessments could not be retrieved, distinguish direct workload
observations from inferred rollup causes, and lower confidence where needed. Do not
invent a health message or claim there are no secondary faults from an empty filter.

## 3. Select findings

Select explicit `Degraded`, `Progressing`, `Missing` or `Unknown` values from the
successful snapshot for the matching leaf. Retain any other explicit unhealthy values
as separate findings. An empty selection establishes no matching assessment only when
the snapshot was successfully obtained and covers the relevant resources; it does not
establish every workload is healthy. For an absent live object, confirm identity,
destination and read result as described in `health-missing.md`.

Sources: [3.0 health storage migration](https://argo-cd.readthedocs.io/en/release-3.4/operator-manual/upgrading/2.14-3.0/#health-status-in-the-application-cr),
[3.4 app get](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/commands/argocd_app_get/),
[3.4 API](https://github.com/argoproj/argo-cd/blob/release-3.4/server/application/application.proto).
