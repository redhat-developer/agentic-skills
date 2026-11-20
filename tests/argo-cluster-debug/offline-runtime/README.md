# Offline runtime behavior evals

These fixtures support cluster-debug evals 41–44. They contain captured-style raw
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

For eval 44, allow shell execution of the simulator and give each run its own log
path under `/tmp`. It starts `/bin/sh` with the skill's shell variables unset and
places mock `oc` and `kubectl` ahead of other commands on `PATH`. Unsupported reads
and all mutation verbs return an error. The simulator records shell commands, CLI
arguments, exit status and output; it does not connect to a cluster. It is a test
double, not a security sandbox or a Lightspeed integration test.

The existing benchmark runner's offline mode grants file reads but not simulator
execution. Run eval 44 through a tool-enabled evaluation agent; do not enable a
live-cluster benchmark merely to obtain shell access. Evals 41–43 can use the
offline benchmark runner with `--fixtures tests/argo-cluster-debug/offline-runtime`.
These cases do not establish new published benchmark scores by themselves.
