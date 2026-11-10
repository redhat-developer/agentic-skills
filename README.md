<p align="center">
  <img src="assets/banner.svg" alt="OpenShift Agent Skills" width="900"/>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome"></a>
  <img src="https://img.shields.io/badge/OpenShift-layered%20products-EE0000.svg" alt="OpenShift">
  <img src="https://img.shields.io/badge/products-1%20shipping%20%7C%203%20open-8A63D2.svg" alt="1 product shipping, 3 open">
  <img src="https://img.shields.io/badge/skills-4-8A63D2.svg" alt="4 skills">
  <img src="https://img.shields.io/badge/evals-61-3FB950.svg" alt="61 evals">
</p>

<p align="center">
  <b>Agent Skills for Red Hat OpenShift layered products.</b><br>
  Generate manifests, audit repos, debug clusters, tune performance, onboard teams.<br>
  <sub>Every skill measured against an unaided baseline — see <a href="#benchmarks">Benchmarks</a>.</sub>
</p>

---

## Install

```shell
# Claude Code
/plugin marketplace add redhat-developer/agentic-skills
/plugin install openshift-gitops@openshift

# Any other agent — Codex, Cline, Amp, Cursor, Antigravity, and 15 more
npx skills add redhat-developer/agentic-skills
```

Then just describe what you need — skills activate on context, you never name them:

```text
"Audit this repo for GitOps best practices"
"Why is my Application stuck OutOfSync?"
"Generate an ApplicationSet with a git directory generator"
```

Skills are plain Markdown with YAML frontmatter, so they are not tied to one agent.
`npx skills` is the [vercel-labs/skills](https://github.com/vercel-labs/skills) CLI — it
reads this repo directly and installs into whichever agent directories it finds.

<details>
<summary><b>Prerequisites</b></summary>

**Required** — `kubectl` **or** `oc`.

**Optional**, each unlocking more capability:

| Tool | Adds |
|------|------|
| `kustomize` | overlay builds during repo audits |
| `kubeconform` | schema validation against Argo CRDs |
| `yq` | YAML-aware parsing and duplicate detection |
| `argocd` | richer Application debugging and sync operations |
| `kubectl-argo-rollouts` | Rollout status and promotion |

```shell
brew bundle     # installs all of the above on macOS
```

</details>

<details>
<summary><b>Codex</b> — manual marketplace entry</summary>

Add to `$REPO_ROOT/.agents/plugins/marketplace.json` or `~/.agents/plugins/marketplace.json`:

```json
{
  "name": "openshift-gitops",
  "category": "Developer Tools",
  "source": {
    "source": "url",
    "url": "https://github.com/redhat-developer/agentic-skills.git",
    "ref": "main"
  },
  "policy": {
    "installation": "AVAILABLE",
    "authentication": "ON_INSTALL"
  }
}
```

Or just use `npx skills add` above, which handles Codex too.

</details>

<details>
<summary><b>GitHub Copilot</b></summary>

```shell
mkdir -p .github/copilot
cp agents/github-copilot/argocd.agent.md .github/copilot/
```

</details>

<details>
<summary><b>Claude Code notes</b></summary>

After install the `argocd` agent appears in `/agents` and the 6 GitOps skills activate on
context. Run `/reload-plugins` if they do not appear immediately.

</details>

## Products

Skills live under `skills/<product>/`, one plugin per product, so you install only what
you run.

| Product | Covers | Skills | Status |
|---------|--------|-------:|--------|
| [**gitops**](skills/gitops) | Argo CD, Argo Rollouts | **4** | shipping, re-measuring |
| [**servicemesh**](skills/servicemesh) | Istio | — | [open for contributions](docs/adding-a-skill.md) |
| [**serverless**](skills/serverless) | Knative | — | [open for contributions](docs/adding-a-skill.md) |
| [**pipelines**](skills/pipelines) | Tekton | — | [open for contributions](docs/adding-a-skill.md) |

Adding skills for your product? Start with **[docs/adding-a-skill.md](docs/adding-a-skill.md)**.
Evals are required — the guide explains the bar and why it is set where it is.

## Usage Guide

> **Full guide with all example prompts:** [docs/USER_GUIDE.md](docs/USER_GUIDE.md)

Skills are grouped by product. Expand the one you use.

<details open>
<summary><b>🔵 GitOps</b> — Argo CD, Argo Rollouts · <b>4 skills</b>, re-measuring</summary>

> **Scope — Red Hat OpenShift GitOps.** These skills cover Argo CD and Argo Rollouts as
> shipped and supported by the OpenShift GitOps operator, including the operator-managed
> CRDs (`ArgoCD`, `RolloutManager`, `NotificationsConfiguration`, `NamespaceManagement`,
> `ImageUpdater`). They work against vanilla Argo CD too, but OpenShift GitOps is the
> target.
>
> **Argo Workflows and Argo Events are deliberately out of scope** — they are separate
> upstream projects the operator does not ship, and on OpenShift pipelines are normally
> [OpenShift Pipelines](https://docs.redhat.com/en/documentation/openshift_pipelines)
> (Tekton). For those, see the [Argo Workflows](https://argo-workflows.readthedocs.io/)
> and [Argo Events](https://argoproj.github.io/argo-events/) docs.
>
> [GitOps Promoter](https://github.com/argoproj-labs/gitops-promoter) **is** covered for
> environment promotion, but is installed separately — it is argoproj-labs, not
> operator-owned.

<sub>Targets Red Hat OpenShift GitOps 1.19+ · Argo CD v2.14+ / v3.x · Argo Rollouts v1.8+.
Measured against OpenShift GitOps 1.21.3 / Argo CD v3.4.5.</sub>

### How the Skills Work Together

The agent automatically selects the right skill based on what you ask:

```
 Ask a question ────► argo-knowledge           "How do I...?"
 Audit a repo ──────► argo-repo-audit          "Audit this repo"
 Debug a cluster ───► argo-cluster-debug       "Why is X failing?"
 Promote a rollout ─► argo-cluster-debug       "Promote / abort / retry the canary"
 Tune performance ──► argo-performance-tuning  "Why is this slow at scale?"
```

You don't need to invoke skills manually — just describe what you need.

### Knowledge — Ask Questions & Generate YAML

<p align="center">
  <img src="assets/screenshots/knowledge-preview.svg" alt="Knowledge Preview" width="820"/>
</p>

Use when you need to understand OpenShift GitOps concepts or generate manifests.

```text
# Generate manifests
Generate a multi-source Application that combines a Helm chart from
oci://registry.example.com/myapp with values from a Git repo.

# Architecture guidance
What's the best way to structure a multi-cluster GitOps repo?
Should I use app-of-apps or ApplicationSet?

# Newer features
How do I set up argocd-agent for 200 edge clusters behind firewalls?
How do I run Applications in any namespace for multi-tenancy?

# OpenShift-specific
Generate an ArgoCD CR for the OpenShift GitOps operator with OAuth and Routes.
```

<details>
<summary>Reference docs included</summary>

| Topic | Reference |
|-------|-----------|
| Application spec, sync policies, health checks, multi-cluster | `applications.md` |
| ApplicationSet generators, progressive syncs, templates | `applicationsets.md` |
| AppProject RBAC, source/destination restrictions, sync windows | `app-projects.md` |
| Image updater annotations, strategies, write-back | `image-updater.md` |
| Repository patterns (app-of-apps, ApplicationSet, monorepo) | `repo-patterns.md` |
| argocd-agent hub-and-spoke architecture | `agent-mode.md` |
| Multi-tenancy, apps-in-any-namespace, Autopilot | `multi-tenancy.md` |
| **Operator-only CRDs** — RolloutManager, NotificationsConfiguration, NamespaceManagement, ImageUpdater, GitopsService | `openshift-gitops-operator.md` |
| GitOps Promoter, PromotionStrategy, branch-per-env promotion, commit status gating | `gitops-promoter.md` |

</details>

### Repo Audit — Security & Best Practice Review

<p align="center">
  <img src="assets/screenshots/audit-preview.svg" alt="Audit Report Preview" width="820"/>
</p>

Use when you want to validate a GitOps repo before deploying or during a review.

```text
# Full audit
Audit the current repo and provide a GitOps report.

# Targeted checks
Check for security issues in my AppProject configurations.
Are there any hardcoded secrets in Helm values?
Do my Applications have proper sync retry configuration?

# Validation only
Just validate YAML syntax and schemas, don't do a full audit.
```

**What it catches:**

| Severity | Examples |
|----------|---------|
| Critical | Wildcard `*` in AppProject sourceRepos/destinations, plain-text Secrets, hardcoded passwords in Helm values, `clusterResourceWhitelist: */*` |
| Warning | Missing syncPolicy, `targetRevision: HEAD` in production, no retry/backoff, missing `ignoreDifferences` for controller-managed fields |
| Info | Missing `ignoreDifferences` for HPA-managed replicas, no progressive sync on multi-cluster ApplicationSets |

### Cluster Debug — Troubleshoot Live Issues

<p align="center">
  <img src="assets/screenshots/debug-preview.svg" alt="Debug Report Preview" width="820"/>
</p>

Use when something is broken or you want a health check.

```text
# Health check
Check if Argo CD is properly installed on my cluster.

# Application issues
Why is my Application podinfo stuck in OutOfSync?
Debug the degraded Application in the production namespace.

# Rollout issues
The canary rollout for frontend is stuck at step 2. Why?
Are my AnalysisTemplates actually testing anything meaningful?

# Multi-tenant review
Compare all ArgoCD instances on this cluster and check for security gaps.

# Deep investigation
Inspect all Rollouts on this cluster and give me a health report.
Review the Argo CD configuration for security concerns.
```

### Performance Tuning — Diagnose & Fix Slowness at Scale

<p align="center">
  <img src="assets/screenshots/performance-preview.svg" alt="Performance Tuning Preview" width="820"/>
</p>

Use when OpenShift GitOps is slow, resource-hungry, or struggling at scale.

```text
# Repo-server under pressure
Our argocd-repo-server keeps getting OOMKilled every time we push to our
  500-application monorepo.

# UI/controller sluggishness
The Argo CD UI feels sluggish and drift detection takes forever with 2,000 apps.

# Multi-cluster scaling
We have 20 clusters registered but only one application-controller pod and
  it's maxed out on CPU.

# Timeout errors
Users see "context deadline exceeded" opening an Application with a huge Helm chart.

# Git provider limits
Our GitHub org is rate-limiting us — 500 apps all point at the same repo and branch.

# Reconciliation churn (no real drift)
Our controller CPU is constantly high even though every Application shows
  Synced/Healthy — nothing in Git has changed.
```

Diagnoses the bottleneck first — including whether the controller is reconciling for the
right reasons at all (`resource.ignoreResourceUpdatesEnabled`, `resource.exclusions`,
per-Application `manifest-generate-paths` cache scoping for monorepos) before reaching for
repo-server concurrency, controller processors, sharding (static or Dynamic Cluster
Distribution), or Git rate-limits — then applies the same **Generate → Preview → Confirm**
safety model as Operations before changing anything live.

<details>
<summary>Reference docs included</summary>

| Topic | Reference |
|-------|-----------|
| Full settings table, per-setting fixes, sharding algorithms, standalone vs. OpenShift GitOps Operator YAML, common mistakes, tuning order of leverage | `tuning-settings.md` |

</details>

## How it works

A skill is a Markdown file with YAML frontmatter. No runtime, no service, no daemon.

```
skills/gitops/argo-cluster-debug/
├── SKILL.md        # always in context once the skill activates — kept short
├── references/     # loaded only when the workflow calls for them
└── scripts/        # deterministic checks the agent runs instead of improvising
```

The agent picks a skill by matching your request against its `description`, so you never
invoke one by name — you describe the problem and the right expertise loads. Reference
files stay out of context until needed, which is why a skill can carry hundreds of lines
of operator-specific detail without consuming the window.

Where being exactly right matters, the skill runs a **script** rather than describing a
procedure. A documented command can be followed loosely; `scripts/validate.sh` cannot.

## Benchmarks

**Every skill in this repo is measured against an unaided baseline** — same model, same
prompts, same live cluster, no access to `skills/`. Graded blind: the grader sees
"Condition A" and "Condition B" and is not told which is which.

That bar applies to every product, not just the one that has skills today. A skill with
no measured baseline is a guess, and this repo does not publish guesses — including when
the answer is unflattering.

<details open>
<summary><b>🔵 GitOps</b> — 4 skills, re-measurement in progress</summary>

> **These numbers are mid-migration.** Two skills were removed and `argo-cluster-debug`
> absorbed Argo Rollouts runtime control, so its scope changed and its old verdict does
> not transfer. This repo does not publish guesses, so rows whose scope changed are
> marked unmeasured rather than carried forward or estimated. There is no weighted
> overall covers only the three skills whose scope did not change (n=324);
> `argo-cluster-debug` is excluded, so it is not a portfolio figure and should not be
> quoted as one.

| Skill | with-skill | baseline | delta | |
|-------|-----------:|---------:|------:|---|
| [`argo-performance-tuning`](benchmarks/argo-performance-tuning.md) | **96.7%** | 64.0% | **+32.7** | scope unchanged |
| [`argo-repo-audit`](benchmarks/argo-repo-audit.md) | **95.3%** | 79.4% | **+15.9** | scope unchanged |
| [`argo-cluster-debug`](benchmarks/argo-cluster-debug.md) | — | — | — | **withdrawn** — gained 19 expectations, must re-measure |
| [`argo-knowledge`](benchmarks/argo-knowledge.md) | — | — | — | **withdrawn** — 4 references cut, scope changed |
| **Weighted overall** | **96.1%** | **70.8%** | **+25.3** | **2 of 4 skills, n=192** — excludes `argo-cluster-debug` and `argo-knowledge` |

**The delta tracks how product-specific a skill is.** Performance tuning — exact setting
names, defaults the operator silently overrides, which CR field actually wins — gains
most. General Argo CD knowledge the model already has gains least.

**Treat direction as reliable and magnitude as not.** Re-running one suite unchanged, on
the same cluster, moved its delta from +4.9 to +9.8 — so anything under ~5 points is
marked *unresolved* above rather than claimed as a win, and even the large numbers are
worth reading as "clearly helps", not as a measurement. The
[methodology page](benchmarks/README.md) has the variance data, and the cases where
fixing our own evals *lowered* a published score.

</details>

<details>
<summary><b>🟣 Service Mesh</b> · <b>🟢 Serverless</b> · <b>🟡 Pipelines</b> — not yet measured</summary>

No skills yet, so nothing to measure. When they land they are held to the same bar:
a strong unaided baseline on the same prompts, blind grading, per-expectation scoring
with evidence, and the numbers published whichever way they come out.

See **[docs/adding-a-skill.md](docs/adding-a-skill.md)** for what that involves.

</details>

→ **[Methodology, grader-variance analysis, and caveats](benchmarks/README.md)** — read
before quoting any of these numbers.

## Safety model

The first question most platform teams ask is *"will this let an agent break my cluster?"*

**The honest answer first: these skills are instructions, not a sandbox.** They tell the
agent to stop and ask before writing, and in measured runs it does. But a Markdown
instruction is followed *most* of the time, not *always* — we have a run where a
documented step was skipped, and the eval caught it. The guarantee you can actually rely
on is the one outside this repo: **the agent can do nothing your `kubeconfig` cannot.**
Scope its RBAC to what you are willing to let it change, and treat everything below as
defence in depth rather than the perimeter.

With that said — **every write is specified to follow the same five steps, stopping at
step 4.**

**1 · Generate** — produces the manifest or command and shows it in full. Nothing runs.

**2 · Preview** — `kubectl diff` for an update, `--dry-run=server --validate=strict` for a
create.
> Never `--dry-run=client`. It validates nothing, and for an update it only echoes your
> input back — it cannot show what would change.

**3 · Blast radius** — resolves what *else* the change touches.
> A diff shows one object. Most Argo CD objects are fan-out points: a one-field edit to an
> `ArgoCD` CR restarts components that every Application on the instance depends on.
> This step names how many Applications stop reconciling, which tenants share the
> instance, and what gets deleted.

**4 · Confirm** — asks explicitly, and waits. Destructive operations require typing the
resource name.

**5 · Verify** — after applying, checks it actually worked and reports the result.

Read-only work — audits, status checks, backups — skips the gate entirely.

**Recommendations carry impact too, not just urgency.** A skill that tells you to raise a
memory limit also tells you that doing so restarts the server and interrupts everyone on
that instance. "How soon" is the easy half; "what else moves" is the half you cannot work
out from the recommendation alone.

```
BLOCKER — Delete Rollout/openshift-gitops/example (no containers; hot-loops the controller)
  Impact: argo-rollouts controller only. The Rollout is invalid so nothing runs from
          it; no workload is affected. Controller restarts once.
```

Three skills (`repo-audit`, `cluster-debug`, `performance-tuning` in diagnosis mode)
contain no write operations at all, so for those the gate never has to fire. If you want
that enforced rather than specified, run the agent with a read-only `kubeconfig` — the
skills behave identically and the question stops being a matter of trust.

## Data and privacy

**The skills send nothing anywhere.** They are inert Markdown and shell scripts in your
checkout — there is no telemetry, no callback, no account.

Be clear about what *your agent* does, though: when it reads cluster state to answer a
question, that output becomes part of the conversation with whichever model you are
using. That is a property of using an AI coding agent at all, not of these skills, but it
is worth knowing before pointing one at a production cluster.

Practical consequences:

- Three skills (`repo-audit`, `cluster-debug`, and `performance-tuning` while diagnosing)
  specify only read operations — no create, apply, patch or delete anywhere in them.
  That is a property of the instructions, not an enforced sandbox; see
  [Safety model](#safety-model).
- The agent acts with **your** credentials and can do nothing your `kubeconfig` cannot.
  This is the only hard limit in the list, and it is the one worth configuring.
- `repo-audit` runs `kubeconform` with `-skip=Secret`, so Secret contents are not sent
  through schema validation.
- **`repo-audit` reports credential locations, not values.** It runs
  `scan-credentials.sh`, which prints file, line, key name and value *length* — enough to
  triage and to find the string yourself, not enough to use it. This replaced a
  documented `grep` that printed whole matching lines; an audit run put a decoded
  username and password into the transcript before it was fixed. The scanner also
  separates real plaintext from SOPS/SealedSecret ciphertext and from values marked
  `# notsecret` or `EXAMPLE-`.
- **That is a property of the script, not a guarantee about the agent.** The skill
  instructs it never to `cat` a Secret or `base64 -d` a value, and the scanner leaks
  nothing by construction — but an agent asked point-blank to show a secret can still
  read the file. Audit a repo holding live credentials with the same care you would give
  to opening that file.

## Contributing

New skills — including for a product not listed above — are welcome. Read
**[docs/adding-a-skill.md](docs/adding-a-skill.md)** first: it covers the eval bar,
baselines, fixtures, and the guards CI enforces.
[CONTRIBUTING.md](CONTRIBUTING.md) covers the mechanics — branches, commits, review.

<details>
<summary><b>Development</b></summary>

```shell
# Install prerequisites (macOS)
brew bundle

# Download Argo CRD schemas for validation (13 schemas, every in-scope kind)
make download-schemas

# Checks — all of these also run in CI
make test-discover        # discovery script against the test fixtures
make test-validate        # YAML syntax, schema validation, kustomize builds
make test-registration    # every skill registered in manifests, agent, banner, README, CI
make test-expectations    # eval expectations' field paths resolve against the CRD schemas

# Evals
make eval                 # all six skills
make eval-knowledge              # no cluster needed
make eval-repo-audit             # no cluster needed
make eval-cluster-debug          # needs a live cluster
make eval-operations             # needs a live cluster
make eval-performance-tuning     # needs a live cluster
make eval-team-onboard           # needs a live cluster
```

Two guards worth knowing about, because they catch the mistakes that actually happened here:

- **`make test-registration`** — a new skill cannot be added without being wired into the
  marketplace manifest, agent definition, Makefile eval targets, banner, README and eval
  workflow. The banner silently lagged two skills behind before this existed.
- **`make test-expectations`** — resolves every `spec.*` path asserted in an eval against
  the committed CRD schemas. Three expectations were found grading *for* manifests the API
  server rejects or prunes; this stops that recurring.

See [AGENTS.md](AGENTS.md) for the repo layout, skill conventions, and eval runner instructions.

</details>

## Support

**This is a community project. It is not a Red Hat product and carries no Red Hat
support.** There is no SLA, no guaranteed response, and no entitlement attached to it.

- Questions, bugs and feature requests: open a [GitHub issue](../../issues).
- Contributions are welcome — see [docs/adding-a-skill.md](docs/adding-a-skill.md).
- Fixes land on a best-effort basis, by whoever has time.

Using these skills does **not** affect the support status of your OpenShift or OpenShift
GitOps subscription. They generate manifests and run read-only commands against your
cluster; nothing here modifies a supported component's configuration without you
approving the change first.

For supported OpenShift GitOps guidance, use
[Red Hat documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops)
and a support case.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## License

[MIT License](LICENSE)
