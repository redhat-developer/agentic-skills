# Offline runtime behavior evals

These fixtures support cluster-debug evals 41–46. They contain captured-style raw
observations, not expected diagnoses. No live cluster is required.

Run each prompt in a fresh agent with `skills/gitops/argo-cluster-debug/SKILL.md`
and its routed references. Do not give the agent the expectations array. Grade its
output and tool trace against that array after the run.

| Eval | Evidence | Additional check |
|---|---|---|
| 41 | `denied-reads.json` | Unattended completion and uncertainty when pod reads are denied |
| 42 | `manual-sync.json`, `caller-schema.json` | Parse the final response and validate it against the supplied schema |
| 43 | `mixed-symptoms.json` | Both independent causal chains survive the workflow handoffs |
| 44 | `fresh-shell.py` simulator | Inspect actual tool calls and the JSONL transcript, not just the final prose |
| 45 | `external-health.json` | Use resource-tree health when Application CR health fields are absent |
| 46 | Captured observations in the prompt | Distinguish unsupported instance scope from an operator fault |

For eval 44, allow shell execution of the simulator and give each run its own log
path under `/tmp`. It interprets newline-separated assignments and direct mock
`oc`/`kubectl` reads with fresh variables on each invocation. It never starts a shell,
resolves an executable, or reads the caller's `PATH`, `HOME` or `KUBECONFIG`. It rejects
unknown commands, absolute executables, substitutions, shell operators and writes.
The transcript records `session`, `cli` and `result` events. This models shell-state
loss; it is not an actual shell or a Lightspeed integration test.

For example, pass these commands as one multiline `--command` argument:

```sh
KCTL=oc
APP=legacy-erp
APP_NS=team-frontend
"$KCTL" get applications.argoproj.io "$APP" -n "$APP_NS" -o json
```

In a separate invocation, set `KCTL=oc`, `NS=team-frontend`, `CR=team-argocd`, then run
`"$KCTL" logs "statefulset/${CR}-application-controller" -n "$NS" --tail=50`.
Run the simulator regression tests with:

```sh
python3 tests/argo-cluster-debug/offline-runtime/test_fresh_shell.py
```

The existing benchmark runner's offline mode grants file reads but not simulator
execution. Run eval 44 through a tool-enabled evaluation agent; do not enable a
live-cluster benchmark merely to obtain shell access. Evals 41–43 and 45–46 can use
the standard offline benchmark targets with identical fixtures for both arms:

```sh
make baseline SKILL=argo-cluster-debug RUN=offline-review ONLY=41,42,43,45,46 FIXTURES=tests/argo-cluster-debug/offline-runtime
make with-skill SKILL=argo-cluster-debug RUN=offline-review ONLY=41,42,43,45,46 FIXTURES=tests/argo-cluster-debug/offline-runtime
```

These cases do not establish new published benchmark scores by themselves.
