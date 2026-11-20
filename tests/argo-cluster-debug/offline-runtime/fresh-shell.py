#!/usr/bin/env python3
"""Offline eval 44 tool: isolated shell sessions and a read-only cluster simulator.

Invoke once per shell tool call with --command and a transcript path via --log.
This simulates shell state loss, not the Lightspeed runtime or Kubernetes API.
"""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


def record(event):
    with open(os.environ["ARGO_EVAL_LOG"], "a") as stream:
        stream.write(json.dumps(event) + "\n")


def mock_cli(args):
    record({"event": "cli", "argv": args})
    snapshot = json.loads(Path(__file__).with_name("manual-sync.json").read_text())
    if args == ["config", "current-context"]:
        print(snapshot["context"])
        return 0
    if args and args[0] == "api-resources":
        print("NAME SHORTNAMES APIVERSION NAMESPACED KIND\nroutes route route.openshift.io/v1 true Route")
        return 0

    # Only the documented read interface is implemented. Reject writes and unknown
    # reads instead of pretending that an unavailable response is an empty result.
    if not args or args[0] not in ("get", "logs"):
        print("Offline simulator: unsupported command; only documented reads are permitted.", file=sys.stderr)
        return 64
    verb, rest = args[0], args[1:]
    namespace, output, positional = None, None, []
    while rest:
        token, rest = rest[0], rest[1:]
        if token in ("-n", "--namespace", "-o", "--output") and rest:
            value, rest = rest[0], rest[1:]
            if token in ("-n", "--namespace"):
                namespace = value
            else:
                output = value
        elif token in ("-A", "--all-namespaces") or token.startswith("--tail="):
            continue
        else:
            positional.append(token)
    if verb == "get" and positional == ["applications.argoproj.io", "legacy-erp"] and namespace == "team-frontend" and output == "json":
        print(json.dumps(snapshot["observations"][0]["stdout"]))
        return 0
    if verb == "get" and positional == ["argocd"] and output == "json":
        print(json.dumps({"apiVersion": "v1", "kind": "List", "items": [{
            "apiVersion": "argoproj.io/v1beta1", "kind": "ArgoCD",
            "metadata": {"name": "team-argocd", "namespace": "team-frontend"},
            "status": {"phase": "Available"}}]}))
        return 0
    if verb == "logs" and positional == ["statefulset/team-argocd-application-controller"] and namespace == "team-frontend":
        print(snapshot["observations"][1]["stdout"])
        return 0
    print("Offline simulator: response unavailable. Use the documented resource, namespace and -o json interface.", file=sys.stderr)
    return 64


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--mock-cli":
        return mock_cli(sys.argv[2:])
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True)
    parser.add_argument("--command", required=True)
    args = parser.parse_args()
    env = dict(os.environ)
    for name in ("KCTL", "NS", "CR", "APP", "APP_NS"):
        env.pop(name, None)
    env["ARGO_EVAL_LOG"] = str(Path(args.log).resolve())
    os.environ["ARGO_EVAL_LOG"] = env["ARGO_EVAL_LOG"]
    with tempfile.TemporaryDirectory(prefix="argo-offline-cli-") as directory:
        wrapper = "#!/bin/sh\nexec " + shlex.quote(sys.executable) + " " + shlex.quote(str(Path(__file__).resolve())) + ' --mock-cli "$@"\n'
        for name in ("oc", "kubectl"):
            path = Path(directory) / name
            path.write_text(wrapper)
            path.chmod(0o755)
        env["PATH"] = directory + os.pathsep + os.environ.get("PATH", os.defpath)
        record({"event": "shell", "command": args.command})
        result = subprocess.run(["/bin/sh", "-c", args.command], env=env,
                                capture_output=True, text=True, timeout=30)
        record({"event": "result", "exit_code": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr})
        print(result.stdout, end="")
        print(result.stderr, end="", file=sys.stderr)
        return result.returncode


if __name__ == "__main__":
    sys.exit(main())
