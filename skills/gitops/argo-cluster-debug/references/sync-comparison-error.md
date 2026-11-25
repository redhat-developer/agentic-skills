<!-- Loaded on demand by app-sync-triage.md when the sync
     status is Unknown or there is a ComparisonError or InvalidSpecError condition.
     Read-only. -->

# Comparison failed

Sync `Unknown` means comparison did not produce a reliable diff. Desired-state
rendering or destination reads may have failed. Use the condition to identify the
layer; cached resource lists and drift counts need freshness checks. Independently
observed workload failures remain valid evidence and require their health procedure.

## 1. Read the condition, not the status

The status is one word. The condition carries the error.

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'
```

| Condition | What failed |
|---|---|
| `ComparisonError` | The desired state could not be built, or the destination could not be read. Repo, revision, render, or cluster. |
| `InvalidSpecError` | Validation failed: project/source/destination policy or existence, repository access, or another spec validation error. Read the message. |
| `UnknownError` | Everything else. Read the message verbatim. |

`InvalidSpecError` is not exclusively policy: Argo CD 3.4 repository validation can
emit it for `repository not accessible`. Route by message to repository checks below,
destination checks in section 4, or policy checks in section 5.
Source: [3.4 validation](https://github.com/argoproj/argo-cd/blob/release-3.4/util/argo/argo.go).

Quote the diagnostic part of the message, redacting credentials and sensitive URL parameters. Most of the diagnosis is in that one string, and
paraphrasing it loses the part that identifies the cause.

## 2. Repo and revision

The most common `ComparisonError`. Message text points at it directly — `repository
not accessible`, `authentication required`, `unable to resolve <ref> to a commit SHA`,
`Unable to resolve 'HEAD' to a commit SHA`.

Reuse the source inventory; otherwise read the routing fields without inline Helm
values, unrelated annotations or credentials:

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath=''\
'single: repo={.spec.source.repoURL} revision={.spec.source.targetRevision} path={.spec.source.path} chart={.spec.source.chart}{"\n"}'\
'{range .spec.sources[*]}source: repo={.repoURL} revision={.targetRevision} path={.path} chart={.chart} ref={.ref} valueFiles={.helm.valueFiles} ignoreMissing={.helm.ignoreMissingValueFiles}{"\n"}{end}'
```

When `sources` is nonempty it supersedes `source`. Preserve its order: source index,
`ref`, requested revision, compared `.status.sync.revisions[]`, and operation
`.status.operationState.syncResult.revisions[]` refer to the same entries. A `$values`
path resolves through the source with `ref: values`, relative to that repository's
root; that source can supply values without generating manifests. Check each implicated
source's authentication/revision separately. Empty single-source fields are not an
invalid multi-source spec.

When credential selection is relevant and access is available, inspect repository and
`repo-creds` URL metadata. Handle read failure before decoding; do not pipe stderr
through a base64 decoder. For example (requires Python 3):

```bash
if REPO_META=$($KCTL get secrets -n "$NS" \
  -l 'argocd.argoproj.io/secret-type in (repository,repo-creds)' \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.argocd\.argoproj\.io/secret-type}{"\t"}{.data.url}{"\n"}{end}'); then
  printf '%s\n' "$REPO_META" | python3 -c '
import base64, json, sys
from urllib.parse import urlsplit, urlunsplit
for line in sys.stdin:
    fields = line.rstrip("\n").split("\t")
    if len(fields) != 3:
        continue
    name, kind, encoded = fields
    try:
        url = base64.b64decode(encoded, validate=True).decode()
        parsed = urlsplit(url)
        if parsed.scheme and parsed.netloc:
            url = urlunsplit((parsed.scheme, parsed.netloc.rsplit("@", 1)[-1], parsed.path, "", ""))
        print(json.dumps({"name": name, "type": kind, "url": url}))
    except (ValueError, UnicodeError):
        print(json.dumps({"name": name, "error": "URL metadata could not be decoded"}))
'
else
  printf '%s\n' 'Repository metadata unavailable; retain the read error as an evidence gap.' >&2
fi
```

Do not print tokens, passwords, SSH keys or credential-bearing URL userinfo/query
parameters. Metadata alone does not prove a credential is valid or present: verify
field presence without values only if needed and permitted. On Forbidden, use the
condition and accessible repo-server logs; do not call inaccessible credentials missing
or retry the unchanged denial.

Repository credentials and `repo-creds` templates are different inputs. A repository
with its own credentials does not inherit a template; otherwise the longest matching
template URL prefix wins after Argo CD URL normalization (3.4 normalizes both URLs). Check the actual URL and protocol: an SSH template does
not match HTTPS. Do not treat every `.git` suffix difference as a credential mismatch.
Some Git hosts require that suffix because Argo CD does not follow their redirect.
Report whether selection, validity or access remains unverified instead of declaring
that a configured credential must work. See [private repository authentication](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/private-repositories/#credential-templates).

Causes that produce this condition without anything being misconfigured: a rotated or
expired token, a deleted branch or tag, a force-push that removed the pinned SHA, and a
private repo reachable from the user's laptop but not from the repo-server pod. For
the last one, inspect network/TLS evidence in repo-server logs rather than assuming credentials:

```bash
$KCTL logs "$REPO_POD" -n "$NS" -c "$REPO_CONTAINER" --since=15m --tail=100 | grep -i -E "error|failed|denied|timeout"
```

## 3. Render failures

Distinguish a renderer error from fetch/authentication/connectivity failures.
`rpc error` alone does not identify the layer; inspect its description and tool output.

```bash
$KCTL logs "$REPO_POD" -n "$NS" -c "$REPO_CONTAINER" --since=15m --tail=200 | grep -i -E "helm|kustomize|plugin|manifest generation"
```

| Tool | What to confirm |
|---|---|
| Helm | Match chart version (`targetRevision`), parameters, values schema and dependencies. Repo-server can build dependencies; an absent local `charts/` directory alone is not proof of failure. Inspect the actual dependency fetch/build error. Check chart-relative `valueFiles` or `$ref` paths and `ignoreMissingValueFiles`: absent optional files are skipped when true. |
| Kustomize | Check missing resources/bases, patch targets, name/selector transformations, remote-base access, and the configured Kustomize version/build options. Reproduce with matching inputs/tool version only when needed. |
| Plugin | The plugin sidecar is running and its name matches `.spec.source.plugin.name`. A renamed or removed plugin fails every Application using it. |

Source: [3.4 Helm values](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/helm/).

The blast radius separates a manifest bug from an infrastructure problem. If several
unrelated Applications are `Unknown` at once, suspect repo-server, egress, or a shared
credential rather than this Application's manifests.

Use already captured sibling failures first. If a shared fault needs confirmation,
query compact status/condition summaries only in the owning instance's watched
namespaces and relevant destination/source. A cluster-wide count of `Unknown` mixes
instances and causes; do not run it as a routine prerequisite.

## 4. The destination cluster

If the desired state renders but the live state cannot be read, the destination is the
suspect. Correlate errors for Applications using the same destination and controller
identity; resource-specific permission failures need not affect every Application.

```bash
$KCTL get applications.argoproj.io "$APP" -n "$APP_NS" \
  -o jsonpath='server={.spec.destination.server}{"\n"}name={.spec.destination.name}{"\n"}'

$KCTL get secrets -n "$NS" -l argocd.argoproj.io/secret-type=cluster \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
```

`spec.destination` accepts either `server` or `name`, not both. A `name` that no cluster
secret declares produces `InvalidSpecError`, not `ComparisonError` — a useful
discriminator when both fields look plausible.

An expired cluster token shows as `ComparisonError` on every Application using that
destination, and the app-controller log names it:

```bash
$KCTL logs "$CONTROLLER_POD" -n "$NS" -c "$CONTROLLER_CONTAINER" --since=15m --tail=200 | grep -i -E "cluster|unauthorized|x509|connection refused"
```

For the in-cluster destination on an operator-managed instance, a controller
authorization denial can indicate a missing or insufficient destination grant. Read
`operator-rbac.md`; establish the exact identity, verb and kind before attributing it.

## 5. InvalidSpecError

When the message identifies policy or an invalid project/source/destination, check
the relevant field. Repository-access messages still follow section 2:

```bash
PROJ=$($KCTL get applications.argoproj.io "$APP" -n "$APP_NS" -o jsonpath='{.spec.project}')
$KCTL get appproject "$PROJ" -n "$NS" -o jsonpath=''\
'destinations={.spec.destinations}{"\n"}'\
'sourceRepos={.spec.sourceRepos}{"\n"}'\
'sourceNamespaces={.spec.sourceNamespaces}{"\n"}'
```

| Message shape | Cause |
|---|---|
| `Application referencing project <p> which does not exist` | The AppProject is absent, or lives in a different namespace from the instance. |
| `application destination ... is not permitted in project` | The destination server or namespace is not in `spec.destinations`. Both fields are matched, and `*` in one does not cover the other. |
| `application repo ... is not permitted in project` | `sourceRepos` does not list the repo. Matching is glob, and is literal about the `.git` suffix. |
| `application '<name>' in namespace '<ns>' is not permitted to use project '<project>'` | The AppProject does not permit this Application's source namespace. Check its `spec.sourceNamespaces`; changing the instance's watch configuration does not fix project permission. See `operator-apps-in-any-namespace.md`. |

The last message is Argo CD's
[`ErrProjectNotPermitted`](https://github.com/argoproj/argo-cd/blob/release-3.4/util/argo/argo.go#L1180).
An instance that does not watch an Application's namespace is a separate gate and
may never update its status. For an unprocessed Application, verify supported instance
scope and the effective watch configuration through `operator-apps-in-any-namespace.md`;
do not infer the watch layer solely from an old status or substitute a different error.

An AppProject rejection and a missing Kubernetes RoleBinding are independent, and both
can be true. Fixing one leaves the other. Say which you checked.

## 6. Report

Name which of the four it is — repo, render, destination, or spec policy — and quote
the condition message. State the blast radius you measured, because "only this
Application" and "every Application on this instance" lead to different fixes even for
an identical message.

State which comparison outputs could not be trusted or refreshed. Do not infer a
current resource count from a failed/stale comparison. Preserve independently verified
live health, operation results and timestamps; report each independent cause rather
than discarding health evidence because comparison failed.
