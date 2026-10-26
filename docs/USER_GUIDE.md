# User Guide — OpenShift Agent Skills

> Covers the **GitOps** product (Argo CD, Argo Rollouts) — the only product with skills
> today. As other products land, their sections go here alongside.

## Quick Start

```shell
# Install the plugin
/plugin marketplace add redhat-developer/agentic-skills
/plugin install argo-skills@argocd

# Verify it loaded
/agents    # should show 'argocd'

# Start using
Audit the current repo for GitOps best practices.
```

## What You Can Ask

The agent automatically picks the right skill based on your prompt. You don't need to specify which skill to use.

### Knowledge — Learn & Generate

```text
# Concepts
What's the difference between app-of-apps and ApplicationSet?
When should I use canary vs blue-green rollouts?
How does argocd-agent work for edge clusters?

# Generate YAML
Generate an Application for my Helm chart at oci://ghcr.io/org/app version 2.x
  with automated sync, prune, selfHeal, and CreateNamespace.

Create an ApplicationSet with git directory generator and progressive syncs
  deploying to staging first, then production at 25%.

Generate a Rollout with canary strategy, Istio traffic management, and a
  Prometheus-based AnalysisTemplate checking error rate < 1%.

# Multi-source
Generate a multi-source Application combining a Helm chart from OCI with
  values from a separate Git repo.

# Notifications
Set up Slack notifications for sync failures with Block Kit formatting
  and GitHub commit status via GitHub App.


# OpenShift
Generate an ArgoCD CR for the OpenShift GitOps operator with OAuth, Routes,
  and resource exclusions for Tekton.

# Promoter
Set up gitops-promoter for environment promotion with commit status gating
  across dev → staging → production.

# Multi-tenancy
Set up apps-in-any-namespace for 3 teams with separate AppProjects, RBAC,
  and namespace-scoped Applications.
```

### Repo Audit — Review & Validate

```text
# Full audit
Audit the current repo and provide a GitOps report.

# Targeted
Check for security issues in my AppProject configurations.
Are there any hardcoded secrets in Helm values?
Do my Applications have proper sync retry configuration?
Are any Applications using targetRevision: HEAD?

# Validation only
Just validate YAML syntax and schemas, don't do a full audit.

# Changed files only
Audit only the files changed in this PR.
```

### Cluster Debug — Troubleshoot

```text
# Health check
Check if Argo CD is properly installed on my cluster.

# Application issues
Why is my Application podinfo stuck in OutOfSync?
Debug the degraded Application in the production namespace.

# Rollout issues
The canary rollout for frontend is stuck at step 2. Why?
Are my AnalysisTemplates actually testing anything meaningful?

# Multi-tenant
Compare all ArgoCD instances on this cluster and check for security gaps.

# Deep investigation
Inspect all Rollouts on this cluster and give me a health report.
Review the Argo CD configuration and RBAC for security concerns.
Analyze the sync wave ordering across my Applications.
```

### Operations — Install, Deploy, Promote, Maintain

Every write operation follows the safety model: **Generate → Preview → Confirm**.

```text
# Setup
Install Argo CD on my OpenShift cluster using the GitOps operator.
Create an AppProject for the frontend team with restricted access.
Add the staging cluster to Argo CD.

# Deploy
Create an Application for this Helm chart with automated sync.
Create an ApplicationSet with git directory generator and progressive syncs.
Set up Slack notifications for sync failures.
Configure the image updater to watch for new tags on my registry.

# Promote
Promote the canary rollout frontend in production.
Sync the Application with server-side apply.
Abort the failing rollout and retry.

# Maintain
Upgrade Argo CD to the latest version.
Back up all my Applications and AppProjects to YAML files.
Rotate the Git credentials for the infra repo.
Migrate deprecated APIs to the latest versions.

# Promoter
Set up gitops-promoter for environment promotion of our payments app.
```

### Performance Tuning — Diagnose & Fix Slowness

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

# No webhooks at scale
We have 5,000 applications and no Git webhooks — baseline CPU is very high
  even when nothing changed.
```

### Team Onboarding — Set Up New Teams on Argo CD

Discovery-first: the skill asks what the team already has (CI, registry, source type,
secrets backend) and generates only the Argo CD pieces — AppProject, Application, RBAC,
namespace, quotas, NetworkPolicies.

**The output is a commit to your GitOps repo, not a `kubectl apply`.** The skill asks
where the repo is and how tenants are laid out in it, writes the config there, shows you
the `git diff`, and hands off to Argo CD to reconcile. The tenant is live once Argo CD
syncs — not at commit time.

```text
# Single team
Onboard the payments team. They use Kustomize, deploy from
  https://github.com/acme/payments.git, need dev/staging/prod namespaces.

# Helm-based team
Onboard analytics — they deploy a Helm chart from OCI registry
  oci://registry.acme.com/charts/analytics with values in a separate config repo.

# Just the security boundary
Generate a scoped AppProject for the frontend team — no wildcards.

# Self-service at scale
Set up self-service onboarding so teams can add themselves via PR.

# Multi-environment with promotion
Onboard the checkout team with gitops-promoter gating dev → staging → prod.
  Production should require manual approval.

# Per-tenant values model (recommended)
Add a new tenant to our onboarding chart — repo is github.com/acme/gitops-platform,
  tenants live under tenant-projects/. Size M, restricted pod security.

# Tenant security baseline
Generate the default NetworkPolicies and Pod Security Standards labels for the
  payments-prod namespace.
```

## Make Commands (Developer)

```shell
# Show all targets
make help

# Download Argo CRD schemas (for kubeconform validation)
make download-schemas

# Run discovery script on test fixtures
make test-discover

# Run validation script on test fixtures
make test-validate

# Run all skill evals
make eval

# Run evals per skill
make eval-knowledge
make eval-repo-audit
make eval-cluster-debug
make eval-operations
make eval-performance-tuning
make eval-team-onboard

# Clean schemas
make clean-schemas
```

## GitHub Actions

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `ci.yml` | Push/PR to main | Validates JSON, YAML syntax, SKILL.md frontmatter |
| `release.yml` | Tag push `v*` | Packages skills as tar.gz/zip, creates GitHub release |
| `evals.yml` | Manual dispatch | Runs evals with model selection (Opus/Sonnet/Haiku) |
| `update-schemas.yml` | Weekly (Monday 9am) | Downloads latest Argo CRD schemas, opens PR if changed |

## Tips

- **Use `oc` or `kubectl`** — the skills work with either. If on OpenShift, `oc` is preferred.
- **Cluster context matters** — the debug and operations skills use your current kubeconfig context. Switch context before asking about a specific cluster.
- **Reference docs load on demand** — the agent loads at most 2 reference files per question. If you need deeper coverage on a topic, ask a follow-up.
- **Safety model** — operations skill always shows what it will change before applying. Say "yes" to apply, anything else to cancel.
- **Argo CD questions redirect** — the platform-engineering skill (openshift-platform-skills) redirects Argo CD questions to argo-skills if both are installed.
