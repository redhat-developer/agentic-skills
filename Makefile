SCHEMAS_DIR := skills/gitops/argo-repo-audit/assets/schemas
SCHEMAS_TMP := $(SCHEMAS_DIR).tmp

DISCOVER_SCRIPT := skills/gitops/argo-repo-audit/scripts/discover.sh
VALIDATE_SCRIPT := skills/gitops/argo-repo-audit/scripts/validate.sh
TEST_DIR := tests/argo-repo-audit
RESULTS_DIR ?= benchmarks/results

ARGOCD_VERSION := v2.14.14
ARGOCD_OPERATOR_VERSION := v0.18.0
ROLLOUTS_MANAGER_VERSION := v0.10.0
IMAGE_UPDATER_VERSION := v1.3.1
ROLLOUTS_VERSION := v1.8.2

.PHONY: help check-numbers baseline with-skill grade hooks hooks-uninstall scan-secrets history history-check download-schemas clean-schemas test-discover test-validate test-registration test-expectations score score-json score-compare eval eval-knowledge eval-repo-audit eval-cluster-debug eval-performance-tuning

# Fetch a CRD schema from an arbitrary URL, selecting the STORAGE version rather than
# versions[0] — the ArgoCD CR serves both v1alpha1 and v1beta1 and we want v1beta1.
# $(1)=url $(2)=output basename
define fetch_schema_url
	@echo "  $(2)"
	@curl -fsSL "$(1)" \
		| yq e -o=json '.spec.versions[] | select(.storage == true) | .schema.openAPIV3Schema' > "$(SCHEMAS_TMP)/$(2).json" \
		|| { echo "ERROR: failed to fetch $(2) from $(1)"; exit 1; }
	@test -s "$(SCHEMAS_TMP)/$(2).json" \
		|| { echo "ERROR: $(2).json is empty — upstream path likely moved"; exit 1; }
	@python3 -m json.tool "$(SCHEMAS_TMP)/$(2).json" > /dev/null \
		|| { echo "ERROR: $(2).json is not valid JSON"; exit 1; }
endef

# Download one CRD schema into the staging dir, failing loudly if upstream moved it.
# $(1)=repo $(2)=version $(3)=upstream CRD filename $(4)=output basename
define fetch_schema
	@echo "  $(4)"
	@curl -fsSL "https://raw.githubusercontent.com/argoproj/$(1)/$(2)/manifests/crds/$(3)" \
		| yq e -o=json '.spec.versions[0].schema.openAPIV3Schema' > "$(SCHEMAS_TMP)/$(4).json" \
		|| { echo "ERROR: failed to fetch $(3) from $(1)@$(2)"; exit 1; }
	@test -s "$(SCHEMAS_TMP)/$(4).json" \
		|| { echo "ERROR: $(4).json is empty — upstream path likely moved ($(3) @ $(1) $(2))"; exit 1; }
	@python3 -m json.tool "$(SCHEMAS_TMP)/$(4).json" > /dev/null \
		|| { echo "ERROR: $(4).json is not valid JSON"; exit 1; }
endef

# Downloads into a staging dir and only swaps it in once every schema is verified, so a
# network blip or an upstream rename can never leave the committed schemas empty/deleted.
download-schemas: ## Download Argo CRD schemas for kubeconform validation
	@rm -rf $(SCHEMAS_TMP) && mkdir -p $(SCHEMAS_TMP)
	@echo "Downloading Argo CD CRDs ($(ARGOCD_VERSION))..."
	$(call fetch_schema,argo-cd,$(ARGOCD_VERSION),application-crd.yaml,application-argoproj-v1alpha1)
	$(call fetch_schema,argo-cd,$(ARGOCD_VERSION),appproject-crd.yaml,appproject-argoproj-v1alpha1)
	$(call fetch_schema,argo-cd,$(ARGOCD_VERSION),applicationset-crd.yaml,applicationset-argoproj-v1alpha1)
	@echo "Downloading ArgoCD CR schema (argocd-operator $(ARGOCD_OPERATOR_VERSION))..."
	$(call fetch_schema_url,https://raw.githubusercontent.com/argoproj-labs/argocd-operator/$(ARGOCD_OPERATOR_VERSION)/config/crd/bases/argoproj.io_argocds.yaml,argocd-argoproj-v1beta1)
	@echo "Downloading OpenShift GitOps operator CRDs..."
	$(call fetch_schema_url,https://raw.githubusercontent.com/argoproj-labs/argocd-operator/$(ARGOCD_OPERATOR_VERSION)/config/crd/bases/argoproj.io_notificationsconfigurations.yaml,notificationsconfiguration-argoproj-v1alpha1)
	$(call fetch_schema_url,https://raw.githubusercontent.com/argoproj-labs/argocd-operator/$(ARGOCD_OPERATOR_VERSION)/config/crd/bases/argoproj.io_namespacemanagements.yaml,namespacemanagement-argoproj-v1beta1)
	$(call fetch_schema_url,https://raw.githubusercontent.com/argoproj-labs/argo-rollouts-manager/$(ROLLOUTS_MANAGER_VERSION)/config/crd/bases/argoproj.io_rolloutmanagers.yaml,rolloutmanager-argoproj-v1alpha1)
	$(call fetch_schema_url,https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/$(IMAGE_UPDATER_VERSION)/config/crd/bases/argocd-image-updater.argoproj.io_imageupdaters.yaml,imageupdater-argocd-image-updater-v1alpha1)
	@echo "Downloading Argo Rollouts CRDs ($(ROLLOUTS_VERSION))..."
	$(call fetch_schema,argo-rollouts,$(ROLLOUTS_VERSION),rollout-crd.yaml,rollout-argoproj-v1alpha1)
	$(call fetch_schema,argo-rollouts,$(ROLLOUTS_VERSION),analysis-template-crd.yaml,analysistemplate-argoproj-v1alpha1)
	$(call fetch_schema,argo-rollouts,$(ROLLOUTS_VERSION),cluster-analysis-template-crd.yaml,clusteranalysistemplate-argoproj-v1alpha1)
	$(call fetch_schema,argo-rollouts,$(ROLLOUTS_VERSION),analysis-run-crd.yaml,analysisrun-argoproj-v1alpha1)
	$(call fetch_schema,argo-rollouts,$(ROLLOUTS_VERSION),experiment-crd.yaml,experiment-argoproj-v1alpha1)
	@rm -rf $(SCHEMAS_DIR) && mv $(SCHEMAS_TMP) $(SCHEMAS_DIR)
	@echo "Done — $$(ls -1 $(SCHEMAS_DIR) | wc -l | tr -d ' ') schemas in $(SCHEMAS_DIR)"

hooks: ## Install the local pre-commit secret scan
	@./scripts/install-git-hooks.sh

hooks-uninstall: ## Remove the local pre-commit hook
	@./scripts/install-git-hooks.sh --uninstall

scan-secrets: ## Scan staged changes for secrets (ARGS=--all for the whole tree)
	@./scripts/scan-secrets.sh $(ARGS)

check-numbers: ## Fail if published scores disagree with benchmarks/results/
	@./scripts/check-published-numbers.py

history: ## Show the benchmark run history and which suites are stale
	@./scripts/record-run.py --report

history-check: ## Fail if benchmarks/results/ holds an unrecorded run
	@./scripts/record-run.py --check

clean-schemas: ## Remove downloaded schemas
	@rm -rf $(SCHEMAS_DIR) $(SCHEMAS_TMP)

test-discover: ## Run discovery script on test fixtures
	$(DISCOVER_SCRIPT) -d $(TEST_DIR)/app-of-apps
	$(DISCOVER_SCRIPT) -d $(TEST_DIR)/applicationset
	$(DISCOVER_SCRIPT) -d $(TEST_DIR)/mixed-issues

score: ## Aggregate eval results into a comparable scorecard (see scripts/score_evals.py)
	@python3 -I scripts/score_evals.py $(RESULTS_DIR)

score-json: ## Same, machine-readable
	@python3 -I scripts/score_evals.py $(RESULTS_DIR) --json

score-compare: ## Diff this run against a prior one: make score-compare PRIOR=path/
	@python3 -I scripts/score_evals.py $(RESULTS_DIR) --compare $(PRIOR)

test-expectations: ## Validate eval expectations' field paths against the Argo CRD schemas
	@bash scripts/check-eval-expectations.sh

test-blast-radius: ## Behavioural tests for scripts/blast-radius.sh (stubbed oc, no cluster needed)
	@bash tests/blast-radius/test.sh

test-registration: ## Check every skill is registered in manifests, agent, Makefile, banner, docs
	@bash scripts/check-skill-registration.sh

test-validate: ## Run validation script on test fixtures
	$(VALIDATE_SCRIPT) -d $(TEST_DIR)/app-of-apps
	$(VALIDATE_SCRIPT) -d $(TEST_DIR)/applicationset

eval: eval-knowledge eval-repo-audit eval-cluster-debug eval-performance-tuning ## Run all skill evals

# --- two-arm benchmarking (scripts/run_eval_arm.py + scripts/grade_eval.py) -------
# The eval-* targets above run the with-skill arm only and self-score; they are a
# smoke test, not a benchmark. A published number needs both arms and a blind grader.
#
#   make baseline SKILL=argo-knowledge RUN=2026-11-10
#   make with-skill SKILL=argo-knowledge RUN=2026-11-10
#   make grade SKILL=argo-knowledge RUN=2026-11-10 LABEL="2026-11-10 run 9"
#   make check-numbers        # already defined above
#
# Add CLUSTER=1 for skills that need read-only oc access (cluster-debug,
# performance-tuning). ONLY=17,18 re-runs a subset.

RUN ?= $(shell date +%F)
MODEL ?= claude-opus-5

baseline: ## Generate the baseline arm (SKILL=, RUN=, [CLUSTER=1], [ONLY=])
	@python3 scripts/run_eval_arm.py --skill $(SKILL) --condition baseline \
		--run-id $(RUN) --model $(MODEL) $(if $(CLUSTER),--cluster,) $(if $(ONLY),--only $(ONLY),)

with-skill: ## Generate the with-skill arm (SKILL=, RUN=, [CLUSTER=1], [ONLY=])
	@python3 scripts/run_eval_arm.py --skill $(SKILL) --condition with-skill \
		--run-id $(RUN) --model $(MODEL) $(if $(CLUSTER),--cluster,) $(if $(ONLY),--only $(ONLY),)

grade: ## Blind-grade both arms into benchmarks/results/ (SKILL=, RUN=, LABEL=)
	@python3 scripts/grade_eval.py --skill $(SKILL) --run-id $(RUN) --model $(MODEL) \
		--run-label "$(LABEL)"


eval-knowledge: ## Run argo-knowledge evals
	@echo "Running argo-knowledge evals..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/gitops/argo-knowledge/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/gitops/argo-knowledge/SKILL.md first, then answers the eval prompt following the skill workflow. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."

eval-repo-audit: ## Run argo-repo-audit evals
	@echo "Running argo-repo-audit evals..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/gitops/argo-repo-audit/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/gitops/argo-repo-audit/SKILL.md first, then follows the audit workflow on the specified test fixture directory. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval name, passed/total, and list any failed expectations."

eval-cluster-debug: ## Run argo-cluster-debug evals (requires live cluster)
	@echo "Running argo-cluster-debug evals (requires kubectl access)..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/gitops/argo-cluster-debug/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/gitops/argo-cluster-debug/SKILL.md first, then follows the debug workflow. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."

eval-performance-tuning: ## Run argo-performance-tuning evals (requires live cluster)
	@echo "Running argo-performance-tuning evals (requires kubectl access)..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/gitops/argo-performance-tuning/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/gitops/argo-performance-tuning/SKILL.md first, then follows the assess/diagnose/tune workflow. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'
