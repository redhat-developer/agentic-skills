# Contributing to OpenShift Agent Skills

Thank you for your interest in contributing! This document provides guidelines
for contributing to this project.

## How to Contribute

### Reporting Issues

- Use [GitHub Issues](https://github.com/redhat-developer/agentic-skills/issues) to report bugs or suggest features
- Include the skill name, agent platform (Claude Code, Copilot, Codex), and steps to reproduce
- For inaccurate YAML generation, include the prompt used and the expected vs actual output

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Make your changes following the conventions below
4. Test your changes (see [Development](#development))
5. Commit with a clear message
6. Push to your fork and open a pull request

### Skill Conventions

- **SKILL.md** files must include frontmatter (`name`, `description`, `license`) and a phased workflow
- Keep SKILL.md under ~15KB — heavy reference material goes in `references/`
- Workflows are explicit step-by-step, not open-ended
- Reference docs are actionable checklists and lookup tables, not tutorials
- Edge cases section prevents false positives on common patterns
- Scripts use awk where possible and avoid dependencies beyond standard POSIX tools

### Reference Documentation

- Use checklist format (`- [ ]`) for best practices and audit items
- Include concrete examples and YAML snippets
- Cite specific API versions — don't leave them ambiguous
- When covering a CRD, verify field names against the actual schema

### Test Fixtures

- Place test fixtures under `tests/{skill-name}/`
- Each fixture should represent a distinct repo pattern or set of issues
- Use realistic but obviously fake data for any credentials or secrets

### Evals

Every skill needs `evals/evals.json`, and the expectations have to be able to tell a
correct answer from a merely plausible one — which is harder than it sounds and is the
most common thing to get wrong.

**Adding a skill, especially from another product team? Start with
[docs/adding-a-skill.md](docs/adding-a-skill.md).** It covers the eval bar, baselines,
fixtures, and the guards, with the specific mistakes we made and how to avoid repeating
them.

## Development

```shell
# Install prerequisites (macOS)
brew bundle

# Download Argo CRD schemas
make download-schemas

# Run discovery script on test fixtures
make test-discover

# Run validation script on test fixtures
make test-validate
```

## Secret scanning

This repo ships a security-auditing skill, so it deliberately contains manifests
that *look* insecure — planted plaintext credentials, wildcard RBAC, insecure TLS.
That makes it unusually easy to trip a secret scanner, and perceived secrets cost
real time: they generate alerts that someone has to triage.

Install the local pre-commit check once:

```sh
make hooks           # installs .git/hooks/pre-commit
make scan-secrets    # run it by hand on staged changes
make scan-secrets ARGS=--all   # whole tracked tree
```

It scans the **index**, not the working tree, so it sees exactly what the commit
will contain. It uses the best scanner you have, in this order:

| Scanner | Patterns | Needs |
|---|---|---|
| `rh-gitleaks` | Red Hat internal — what PwnedAlert runs | Red Hat VPN + a token |
| `leaktk-gitleaks7` | public leaktk patterns | nothing |
| `gitleaks` | whatever upstream build you have | nothing |

If none is installed it warns and lets the commit through, rather than blocking
outside contributors — but it says plainly that the commit was not verified.

**Red Hat contributors** can additionally install `rh-gitleaks` to reproduce
exactly what PwnedAlert will flag. It is intentionally *not* wired in via
`.pre-commit-config.yaml`: this repository is public, `rh-pre-commit` lives on
internal GitLab and installs only over the VPN, so committing that config would
break `pre-commit install` for everyone outside Red Hat. Red Hat InfoSec's own
documentation recommends keeping it local for exactly this reason.

### When the scan flags something

Real secret — do not commit it, and rotate it if it has existed anywhere.

False positive, in rough order of preference:

1. Make the value obviously fake. Prefix it with `EXAMPLE-` and keep it short;
   `EXAMPLE-password#1` reads as fake, `1ns3rtP@$$w0rd` does not.
2. Add a trailing `# notsecret` comment on the line.
3. Allowlist it in [`.gitleaks.toml`](.gitleaks.toml) — matching the **value**
   rather than a path wherever possible, and never anchoring a path with `^`
   (the hook scans from a temp directory, where an anchored path will not match).

Red Hat InfoSec deliberately does **not** tune out secret-shaped strings in test
data, on the grounds that people sometimes commit real secrets to tests. So
fixtures have to be handled here rather than reported upstream as false positives.

## Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
