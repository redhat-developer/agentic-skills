# Operator troubleshooting references

Known operator symptoms route directly from `../SKILL.md` to the guides below.
This index preserves links from other skills; it contains no separate troubleshooting
workflow. Reuse current-run installation evidence and read the applicable guide
before choosing operator-specific checks or proposing remediation.

| Symptom | Required reference |
|---|---|
| Controller authorization failure in a destination namespace | `operator-rbac.md` |
| Ignored Application outside the instance namespace, source-namespace project rejection or UI access after moving an Application | `operator-apps-in-any-namespace.md` |
| Correct input but generated objects absent on a supported instance | Workflow 6 in `debug-workflows.md` |

Diagnosis is read-only. Configure operator inputs, not generated Roles, RoleBindings,
ConfigMaps or workload flags. If a required guide cannot be read, report that limitation;
continue accessible evidence checks without inventing the missing procedure.
For a caller-supplied output schema, read `runtime-output.md`; otherwise use
`report-format.md`.
