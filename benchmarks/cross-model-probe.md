# Cross-model probe — does skill value survive a model generation?

**2026-11-10 · claude-opus-4-6 vs claude-opus-5 · 16 evals · 132 expectations per arm**

> **Different harness from the rest of `benchmarks/`.** These numbers are NOT comparable
> to the run-N pages. Only the four arms here are comparable to each other.

Every published run in this repo used a single model (`claude-opus-5`, runs 1–8), so
nothing measured whether a skill's value decays as the base model improves. That matters
because this repo's organising rule is *"encode what is version- and product-specific; do
not re-encode what the model already knows"* — and what the model knows moves.

## Result

| arm | score | delta |
|---|--:|--:|
| `claude-opus-4-6` baseline | 69.7% | |
| `claude-opus-4-6` with-skill | **94.3%** | **+24.6** |
| `claude-opus-5` baseline | 84.5% | |
| `claude-opus-5` with-skill | **96.2%** | **+11.7** |

The skill is worth **more than twice as much** on the older model. The baseline climbed
69.7% → 84.5% between generations while the with-skill ceiling barely moved
(94.3% → 96.2%): newer models close the gap from below rather than being lifted higher.
Skill value decays as models improve — but at +11.7 it has not vanished.

## Per eval

| eval | reference routed to | n | 4.6 base | 4.6 skill | Δ 4.6 | o5 base | o5 skill | Δ o5 |
|---|---|--:|--:|--:|--:|--:|--:|--:|
| 1 | `applications + patterns` | 12 | 88% | 96% | **+8** | 96% | 96% | **+0** |
| 2 | `applicationsets` | 10 | 85% | 90% | **+5** | 100% | 95% | **-5** |
| 3 | `rollouts` | 10 | 100% | 100% | **+0** | 100% | 100% | **+0** |
| 4 | `notifications` | 10 | 100% | 100% | **+0** | 100% | 90% | **-10** |
| 5 | `openshift` | 12 | 100% | 100% | **+0** | 100% | 100% | **+0** |
| 6 | `multi-tenancy` | 12 | 79% | 92% | **+12** | 92% | 100% | **+8** |
| 7 | `agent-mode` | 10 | 60% | 100% | **+40** | 100% | 100% | **+0** |
| 8 | `gitops-promoter` | 12 | 46% | 100% | **+54** | 75% | 92% | **+17** |
| 9 | `operator` | 6 | 58% | 100% | **+42** | 50% | 100% | **+50** |
| 10 | `operator` | 5 | 0% | 100% | **+100** | 100% | 100% | **+0** |
| 11 | `operator` | 5 | 0% | 90% | **+90** | 40% | 100% | **+60** |
| 12 | `operator` | 5 | 40% | 100% | **+60** | 50% | 100% | **+50** |
| 13 | `operator + image-updater` | 7 | 14% | 86% | **+71** | 21% | 100% | **+79** |
| 14 | `best-practices + openshift` | 5 | 80% | 90% | **+10** | 90% | 90% | **+0** |
| 15 | `best-practices` | 5 | 100% | 90% | **-10** | 100% | 90% | **-10** |
| 16 | `repo-patterns` | 6 | 75% | 58% | **-17** | 75% | 83% | **+8** |

## What was cut, and why

Four references tied or lost against an unaided baseline on **both** models:
`rollouts.md` (551), `openshift.md` (282), `notifications.md` (562),
`best-practices.md` (359) — 1,754 lines, 33% of the corpus. Eval 14's tracking-method
content was salvaged into `openshift-gitops-operator.md` first, since both of its
backing references were being cut.

`openshift-gitops-operator.md` and `image-updater.md` are the value proposition: five
evals, +46 to +79 on both models. That is exactly the operator-specific content the
narrowing was meant to concentrate on.

`agent-mode.md` is the one clean **absorption** case — +40 on 4.6, +0 on opus-5. Kept,
because this repo ships to Codex, Cline, Cursor and others that may run weaker models. A
skill is partly a portability layer, and a single-model snapshot cannot tell "never
needed" from "newer model absorbed it".

`gitops-promoter.md` scored +4 in the published run and **+54 / +17** here — it is
load-bearing, not marginal.

## Method

- **with-skill** = `SKILL.md` plus the reference(s) its routing table points at for that
  eval, inlined into the prompt. **baseline** = the eval prompt alone. Inlining removes
  the confound where a with-skill arm scores badly only because the agent never opened
  the file.
- No tools, no cluster, no repo access in either arm — this measures knowledge, not
  tool use. That is the main reason it is not comparable to the run-N pages.
- One fixed grader (`claude-opus-5`) for all four arms. Arms shuffled to A/B/C/D per
  eval; the grader was not told which was which. Per-expectation pass/partial/fail with
  a verbatim evidence quote.
- Grader drift is documented at −6.9 to +0.9 in this repo; holding the grader fixed
  keeps it out of the comparison.

## Caveats

Per-eval n is 5–12 and the largest swings sit on the smallest samples — eval 10 moves
0% → 100% on n=5. **The aggregate is the trustworthy figure; per-file deltas under ~10
points are not.** Single run, no repeats.

`app-projects.md` (308 lines) has no eval in the suite and remains unmeasured. It was
not cut, because absence of measurement is not evidence of absence of value.
