# Adding a skill

A guide for OpenShift layered-product teams contributing skills here — Service Mesh,
Serverless, Pipelines, anything else. It covers what a skill must contain, and in
particular what its evals must do, because that is the part most contributions get wrong.

**This is a monorepo.** You contribute by PR into this repository and CI enforces the bar
below rather than trusting it was met. Product areas already exist as
[`skills/servicemesh/`](../skills/servicemesh), [`skills/serverless/`](../skills/serverless)
and [`skills/pipelines/`](../skills/pipelines), each with a README listing likely first
skills.

The short version: **a skill without evals is a guess**. We have measured skills in this
repo that looked excellent and did not beat an unaided model, and we only found out
because the evals existed. On first measurement only two of six cleared the noise floor;
one scored *below* its unaided baseline.

---

## 1. What you are signing up for

| Required | Why |
|----------|-----|
| `SKILL.md` with `name` + `description` frontmatter | How agents discover and route to it |
| An eval suite (`evals/evals.json`) | Without it nobody can tell whether the skill helps |
| A measured baseline | "90%" means nothing alone; the question is 90% versus *what* |
| Passing the repo guards | `make test-registration test-expectations check-numbers history-check` |

Budget real time for the evals. For the skills here they were roughly half the total
effort, and they are what caught every serious defect.

---

## 2. Layout

```
skills/<product>/              # gitops, servicemesh, serverless, pipelines, ...
├── _schemas/                  # optional; CRD schemas for YOUR product (see below)
└── <skill-name>/
    ├── SKILL.md               # entry point; keep it short, it is always in context
    ├── references/            # loaded on demand, not up front
    │   └── <topic>.md
    ├── scripts/               # optional; deterministic beats prose (see §4)
    └── evals/
        └── evals.json
```

`<product>` is the OpenShift layered offering. There is deliberately no `openshift/`
level — everything here is OpenShift, so it would be redundant on every path.

**Product CRD schemas.** `make test-expectations` validates any `spec.*` path your
expectations assert against committed CRD schemas, catching expectations that grade *for*
a field the API would reject. Schemas are per product: put them in
`skills/<product>/_schemas/` as JSON (one file per CRD, the `openAPIV3Schema` object).
Until that directory exists your paths are reported **unvalidated** rather than failed —
the guard will not block your first PR, but it will not protect you either.

`gitops` is the exception and not the pattern to copy: its 13 schemas predate the
convention and live in `skills/gitops/argo-repo-audit/assets/schemas/`, because the
repo-audit skill ships them as a runtime asset. `schema_dir_for()` falls back to that
path for `gitops` alone. Use `_schemas/` for a new product. See `make download-schemas`
for how the Argo set is fetched and pinned to specific upstream versions — pin yours the
same way, so a schema change upstream cannot silently alter what your evals accept.

`SKILL.md` frontmatter needs at minimum:

```yaml
---
name: mesh-traffic-debug          # lowercase, hyphens, unique across the repo
description: >
  One paragraph covering what it does AND when to use it. Agents route on this
  text, so be concrete about triggers and explicit about what is out of scope.
---
```

Keep `SKILL.md` lean and push detail into `references/`. It is loaded every time the
skill activates; reference files are not.

### Compass manifest

Each skill needs a `catalog-info.yaml` in its directory for catalog registration:

1. Create `skills/<product>/<skill>/catalog-info.yaml` — use an existing skill as template
2. Set the `metadata.description` to match your `SKILL.md` frontmatter `description`
   exactly (normalized whitespace). `make test-registration` enforces this using
   [yq](https://github.com/mikefarah/yq) (installed by CI; `brew install yq` locally).
3. Add the manifest as a `spec.targets` entry in the root `catalog-info.yaml`

---

## 3. Writing evals that measure something

This is the part worth reading twice.

### An eval is a prompt plus expectations

```json
{
  "evals": [
    {
      "id": 1,
      "name": "Sidecar not injecting",
      "prompt": "Pods in my namespace have no sidecar. Debug it.",
      "expectations": [
        "Checks the namespace for the injection label",
        "Checks whether the webhook configuration exists and matches the namespace",
        "..."
      ]
    }
  ]
}
```

Aim for **5–8 expectations per eval**, each independently gradeable. Partial credit is
supported (`pass` / `partial` / `fail`), so expectations can be demanding.

### The failure that matters most: expectations that cannot discriminate

An expectation like *"produces a report with root cause and recommendations"* is
satisfied by naming **any plausible cause**. It cannot tell a correct diagnosis from a
confident wrong one — so it scores both identically and measures nothing.

We hit this exactly. Two scenarios where the skill arm reached the **right** root cause
and the baseline reached a **wrong** one scored the same, and the suite reported a 0.0
delta. Rewriting the expectations moved the same two answers from +0.0 to +13.3.

Write expectations that name something checkable:

```
BAD   Produces a report with root cause and recommendations
BAD   Identifies the root cause
BAD   Diagnoses the issue correctly

GOOD  Names the specific failing object and the field that establishes it
GOOD  Every root cause asserted is backed by the observation that establishes it
      (a field value, pod phase, restart count, condition, or log line actually
      shown). A cause asserted with no supporting output, or contradicted by
      output shown elsewhere in the same answer, fails this expectation even if
      it is plausible and well written.
```

That last clause is the workhorse. It is what separates "sounds right" from "is right".

### Four more traps, all of which bit us

1. **Expectations about resources that do not exist.** If a prompt names
   `Application podinfo` and no such thing exists on the test cluster, every expectation
   requiring a real finding is capped at `partial` for *both* arms — the eval measures
   nothing. Either deploy a fixture (§5) or rewrite the expectation to grade the method
   and say so explicitly.

2. **Expectations that presume a field the object lacks.** One of ours asked whether
   `maxUpdate` was satisfied on an object where `maxUpdate` was never set. Nothing could
   satisfy it.

3. **Expectations that force one reading of ambiguous evidence.** We wrote "if the error
   names one source, the report must not attribute the failure to the other" — but the
   tool blames the source it is *rendering* while the fault is elsewhere, so the clause
   penalised the correct answer. Fix the ambiguity in the fixture; do not legislate a
   reading.

4. **Contradictory expectation pairs.** Two expectations in different evals that cannot
   both be satisfied cap the whole suite. `make test-expectations` will not catch this —
   read your suite end to end.

### Validate before you run anything

```bash
make test-expectations     # every spec.* path you assert must resolve against a real CRD schema
```

This catches expectations that grade *for* a field that does not exist — i.e. rewarding
an answer for producing a manifest the API would reject. It exists because we shipped
exactly that: an expectation asserting a field at the wrong nesting level, which the
eval then rewarded the model for reproducing.

---

## 4. Prose is not enforcement

A `SKILL.md` instruction is followed sometimes. We shipped a 12-step debugging workflow
whose steps 10–11 prescribed exactly the right check; a measured run stopped at step 9 and
failed that expectation. The content was there; the adherence was not.

So where correctness matters, prefer in this order:

1. **A script** the skill invokes (`scripts/`). Deterministic and testable — see
   `skills/gitops/argo-repo-audit/scripts/validate.sh` or `scripts/blast-radius.sh`.
2. **An eval expectation** that fails when the step is skipped. This is what makes
   adherence visible at all.
3. **Prose**, for everything else.

And test any command you document. Several of ours were wrong until run against a real
cluster: a label selector that matched nothing, a `jsonpath` that crashed on an empty
result instead of returning nothing, and a `grep` pipeline that returned **zero** on the
very fixture built to exercise it.

---

## 5. Fixtures

If your evals need cluster state, ship it as code so anyone can reproduce the run:

```
tests/<skill-name>/fixtures/
├── manifests.yaml
├── setup.sh       # deploy and arm the symptoms
└── teardown.sh    # remove, and VERIFY nothing is left behind
```

Label everything (`<product>-eval-fixture=true`) so teardown is unambiguous, and have
`teardown.sh` fail loudly if anything survives. See
`tests/argo-cluster-debug/fixtures/` for a worked example.

---

## 6. Benchmarks: measure against a real baseline

A score on its own is meaningless. Every skill is measured twice on the same prompts:

- **with-skill** — the agent reads your `SKILL.md`
- **baseline** — the same model, same prompts, same tools, same cluster, **no access to
  `skills/`**

Then graded **blind**: the grader sees "Condition A" and "Condition B" and is not told
which is which.

**How to actually run it:**

```bash
make baseline   SKILL=<your-skill> RUN=$(date +%F)   # add CLUSTER=1 if it needs one
make with-skill SKILL=<your-skill> RUN=$(date +%F)
make grade      SKILL=<your-skill> RUN=$(date +%F) LABEL="2026-11-10 run N"
make check-numbers
```

`make grade` writes `benchmarks/results/<skill>.{with-skill,baseline}.results.json`, and
`make check-numbers` then fails until every published table matches those verdicts. Add
`--require-state` (see `scripts/run_eval_arm.py --help`) for cluster fixtures, and run
cluster-dependent arms **sequentially** — run in parallel they can perturb each other's
view of the cluster, which silently invalidates the comparison rather than failing it.

Note the `make eval-*` targets are a different thing: with-skill only, self-scored. They
are a smoke test, not a benchmark.

**Make the baseline strong.** A hobbled baseline produces a flattering number that tells
you nothing. Several of ours beat the skill on specific items, and that is how we learned
what to fix.

**Do not contaminate it.** We told two baselines to "stop before writing" — which is part
of what those evals measured. It inflated the apparent benefit until we re-ran them.

**Know the noise floor.** Regrading *identical* text with a fresh grader moved scores by
up to 7 points, with disagreements almost entirely one-directional (`pass` → `partial`).
Within a single run both arms share one grader, so direction and rank-ordering are
trustworthy; absolute values across runs are not. **Treat anything under ~5 points as
unresolved.**

Record every run so scores stay interpretable:

```bash
scripts/record-run.py benchmarks/results --run <id> --date YYYY-MM-DD
make history          # shows which suites are stale and why
```

Each record stores a `suite_fp` — a hash of the exact expectations graded. Two scores are
comparable only if their fingerprints match. Reword an expectation and the old number
stops being current; the tooling says so rather than leaving it to memory.

---

## 7. Before you open the PR

```bash
make test-registration    # skill registered everywhere it needs to be
make test-expectations    # asserted spec.* paths resolve against real CRD schemas
make check-numbers        # published scores match the verdict files
make history-check        # every result file is recorded
make hooks                # install the local secret-scan pre-commit hook (once)
```

Registration is strict on purpose: a new skill must appear in `marketplace.json`, the
agent's skills list, a Makefile eval target *and* the `eval` aggregate, the banner, the
README, and both `evals.yml` entries. It also verifies that each skill has a
`catalog-info.yaml` Compass manifest, that the root `catalog-info.yaml` Location lists it
as a target, and that the manifest description has not drifted from the SKILL.md
frontmatter. The guard lists anything missing.

**On secrets:** this repo deliberately contains insecure-looking manifests as audit
fixtures, so scanners trip easily. Prefix synthetic credentials with `EXAMPLE-`, keep them
short, and add `# notsecret` on the line. Red Hat InfoSec deliberately does *not* tune out
secret-shaped strings in test data, so handle it here rather than reporting it upstream.

### Checklist

- [ ] `SKILL.md` has `name` + `description`; detail lives in `references/`
- [ ] Out-of-scope products stated explicitly in the description
- [ ] Evals exist, 5–8 expectations each, none of them generic
- [ ] Every expectation names something checkable; grounding clause where diagnosis matters
- [ ] No expectation presumes a field or resource that is absent
- [ ] Fixtures committed with `setup.sh` and a verifying `teardown.sh`, if needed
- [ ] Baseline run, uncontaminated, graded blind
- [ ] Run recorded with `record-run.py`; `make history` shows no stale suite
- [ ] All five `make` guards pass

---

## Screenshots

Each skill in the README carries a preview showing what the skill actually produces.
They sell the skill better than prose does, and a product tab without them looks
unfinished.

They are **hand-written SVG, not screen captures** — deliberately. SVGs stay sharp on
every display, diff as text in review, never leak a real cluster name or token, and can
be corrected when the skill's output changes. A PNG of a terminal goes stale invisibly.

Convention, matching the existing set in `assets/screenshots/`:

- `assets/screenshots/<short-name>-preview.svg`, e.g. `audit-preview.svg`
- `viewBox="0 0 820 <height>"` — 820 wide, height to fit (existing ones run 360–460)
- A terminal chrome frame: title bar with the three dots, the skill name and the scenario
- Show a **real** interaction: the prompt a user types, then the salient part of the
  output. Use genuine field names and genuine error text — an invented error teaches the
  reader the wrong thing to search for.
- Call out the insight with a short annotation (`← no oci:// scheme`), which is the part
  a reader actually takes away.
- Redact nothing real: use `EXAMPLE-` values and placeholder hostnames, never a live
  cluster's.

Reference it from the README inside your product's tab:

```markdown
<p align="center">
  <img src="assets/screenshots/<short-name>-preview.svg" alt="<Skill> Preview" width="820"/>
</p>
```

Render it before committing — `qlmanage -t -s 900 -o /tmp assets/screenshots/x.svg` on
macOS, or open it in a browser. Several of ours had text overflowing the frame until
they were actually looked at.

## Adding a new product area

If your product has no directory yet:

1. `skills/<product>/README.md` describing scope. **No `SKILL.md`** — a placeholder skill
   is discovered by `npx skills add` and installed by everyone.
2. A plugin entry in `.claude-plugin/marketplace.json`. One plugin per product;
   `openshift-gitops` is the worked example, so users install only what they need.
3. Per skill: `benchmarks/<skill>.md` and a `make eval-<short>` target wired into the
   `eval` aggregate. The registration guard enumerates everything it expects and names
   what is missing — run it early rather than guessing.

## Questions

Open an issue. If you are unsure whether an expectation is strong enough, paste it in the
issue — that is the most common thing to get wrong and the cheapest to fix before you have
built a whole suite around it.
