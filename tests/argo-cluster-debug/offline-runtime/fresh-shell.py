#!/usr/bin/env python3
"""Offline eval 44: a restricted command interpreter with fresh variable state.

--command accepts newline-separated assignments and documented oc/kubectl reads.
Only KCTL, NS, CR, APP and APP_NS variables are supported. This is deliberately
not a shell: there are no processes, environment access, file reads through commands,
substitutions, control flow, pipelines, redirects, or arbitrary executable paths.
"""
import argparse
import json
from pathlib import Path
import re
import shlex
import sys


VARIABLES = frozenset(("KCTL", "NS", "CR", "APP", "APP_NS"))
REFERENCE = re.compile(r"\$(?:\{([A-Za-z_][A-Za-z_0-9]*)\}|([A-Za-z_][A-Za-z_0-9]*))")
ASSIGNMENT = re.compile(r"([A-Za-z_][A-Za-z_0-9]*)=(.*)", re.DOTALL)


class UnsupportedCommand(ValueError):
    """The input is outside the simulator's explicit command language."""


def expand(token, variables):
    def value(match):
        name = match.group(1) or match.group(2)
        if name not in variables:
            raise UnsupportedCommand(f"variable {name} is unset in this session")
        return variables[name]

    result = REFERENCE.sub(value, token)
    if "$" in result:
        raise UnsupportedCommand("unsupported variable expansion")
    return result


def parse_commands(command):
    """Resolve a whole session before producing any simulated CLI observations."""
    variables, commands = {}, []
    for line in command.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        # Reject shell syntax even inside quotes: the supported language only needs
        # identifiers, resource names, literal flags and the five variables above.
        if any(char in line for char in ";|&<>`()\\"):
            raise UnsupportedCommand("shell operators and substitutions are unsupported")
        try:
            tokens = shlex.split(line, comments=True)
        except ValueError as error:
            raise UnsupportedCommand(str(error)) from error
        if not tokens:
            continue
        assignment = ASSIGNMENT.fullmatch(tokens[0])
        if assignment:
            name, value = assignment.groups()
            if len(tokens) != 1 or name not in VARIABLES:
                raise UnsupportedCommand("use a standalone assignment to a supported variable")
            variables[name] = expand(value, variables)
            continue
        args = [expand(token, variables) for token in tokens]
        if args[0] not in ("oc", "kubectl"):
            raise UnsupportedCommand("only the simulated oc and kubectl commands are available")
        commands.append(args)
    if not commands:
        raise UnsupportedCommand("session must include a documented read command")
    return commands


def mock_cli(args, snapshot):
    if args == ["config", "current-context"]:
        return snapshot["context"]
    if args in (["api-resources"], ["api-resources", "--api-group=route.openshift.io"]):
        return "NAME SHORTNAMES APIVERSION NAMESPACED KIND\nroutes route route.openshift.io/v1 true Route"
    if not args or args[0] not in ("get", "logs"):
        raise UnsupportedCommand("only documented reads are permitted")

    verb, rest = args[0], list(args[1:])
    flags, positional = {}, []
    aliases = {"-n": "namespace", "--namespace": "namespace", "-o": "output", "--output": "output"}
    while rest:
        token = rest.pop(0)
        if token in aliases:
            key = aliases[token]
            if not rest or key in flags:
                raise UnsupportedCommand("missing or repeated flag value")
            flags[key] = rest.pop(0)
        elif token in ("-A", "--all-namespaces"):
            if "all" in flags:
                raise UnsupportedCommand("repeated all-namespaces flag")
            flags["all"] = True
        elif token == "--tail=50":
            if "tail" in flags:
                raise UnsupportedCommand("repeated tail flag")
            flags["tail"] = 50
        elif token.startswith("-"):
            raise UnsupportedCommand(f"unsupported flag: {token}")
        else:
            positional.append(token)

    if verb == "get" and positional == ["applications.argoproj.io", "legacy-erp"] and flags == {"namespace": "team-frontend", "output": "json"}:
        return json.dumps(snapshot["observations"][0]["stdout"])
    if verb == "get" and positional == ["argocd"] and flags == {"all": True, "output": "json"}:
        return json.dumps({"apiVersion": "v1", "kind": "List", "items": [{
            "apiVersion": "argoproj.io/v1beta1", "kind": "ArgoCD",
            "metadata": {"name": "team-argocd", "namespace": "team-frontend"},
            "status": {"phase": "Available"}}]})
    if verb == "logs" and positional == ["statefulset/team-argocd-application-controller"] and flags == {"namespace": "team-frontend", "tail": 50}:
        return snapshot["observations"][1]["stdout"]
    raise UnsupportedCommand("response unavailable; use the documented resource, namespace and flags")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True)
    parser.add_argument("--command", required=True)
    args = parser.parse_args()
    events = [{"event": "session", "command": args.command}]
    try:
        commands = parse_commands(args.command)
        snapshot = json.loads(Path(__file__).with_name("manual-sync.json").read_text())
        # Validate every requested read before publishing any output. Unsupported
        # requests fail closed, with no partial success and no external fallback.
        outputs = [mock_cli(command[1:], snapshot) for command in commands]
        events.extend({"event": "cli", "argv": command[1:]} for command in commands)
        stdout, stderr, code = "\n".join(outputs) + "\n", "", 0
    except UnsupportedCommand as error:
        stdout, stderr, code = "", f"Offline simulator: {error}.\n", 64
    events.append({"event": "result", "exit_code": code, "stdout": stdout, "stderr": stderr})
    with Path(args.log).open("a") as stream:
        for event in events:
            stream.write(json.dumps(event) + "\n")
    print(stdout, end="")
    print(stderr, end="", file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
