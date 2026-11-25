# When the named resource does not exist

Verify the requested cluster context, API resource, exact name and namespace before
troubleshooting. Reuse established context, candidate namespaces and instance evidence;
never silently substitute another object.

## Resolve the resource type

Use `applications.argoproj.io` for Argo CD Applications and
`subscriptions.operators.coreos.com` for OLM Subscriptions. Bare `application` or
`subscription` can resolve to another API group on ACM/MCE clusters. Resolution uses
discovery priorities, not a guaranteed alphabetical choice. Check the group named in
the error before interpreting `NotFound`.

For an unfamiliar kind, inspect accessible API discovery for its group, plural name,
kind and short names. Matching only the first `api-resources` column cannot rule out
ambiguity: that column is the plural resource name. A denied discovery read leaves
the type unresolved, not absent. Reuse discovery already collected.

## Locate the exact object

Start in the requested namespace with the fully qualified resource type. Only widen
a successful empty/NotFound lookup if the current-run inventory does not cover it:

```bash
$KCTL get applications.argoproj.io -A --field-selector metadata.name="$APP" \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name
# Only if deletion is plausible; absence of events does not prove deletion.
$KCTL get events -n "$APP_NS" --field-selector involvedObject.name="$APP" \
  --sort-by=.lastTimestamp | tail -5
```

Preserve read errors. A denied search leaves the object unresolved; it does not prove
absence. After a successful empty exact-name search, check likely typos in accessible
candidate namespaces. If context or ownership remains unknown, use Workflow 1 in
`debug-workflows.md`; otherwise do not repeat installation discovery.

Report the identity and namespaces searched, what was found, and unavailable checks.
Do not infer deletion from an empty lookup alone. If demonstrating checks on a different
resource, label it explicitly as a demonstration, not the requested diagnosis.
