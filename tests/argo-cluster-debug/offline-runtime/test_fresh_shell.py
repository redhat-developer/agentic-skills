#!/usr/bin/env python3
"""Regression checks for the offline interpreter; never invokes a real cluster CLI."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SIMULATOR = Path(__file__).with_name("fresh-shell.py")
APP_READ = "oc get applications.argoproj.io legacy-erp -n team-frontend -o json"
LOG_READ = "oc logs statefulset/team-argocd-application-controller -n team-frontend --tail=50"


class OfflineInterpreterTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="argo-simulator-test-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.log = self.root / "trace.jsonl"

    def run_command(self, command, env=None):
        return subprocess.run(
            [sys.executable, str(SIMULATOR), "--log", str(self.log), "--command", command],
            env=env, capture_output=True, text=True, timeout=10,
        )

    def events(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_application_and_log_reads_in_independent_sessions(self):
        application = self.run_command(
            'KCTL=oc\nAPP=legacy-erp\nAPP_NS=team-frontend\n'
            '"$KCTL" get applications.argoproj.io "$APP" -n "$APP_NS" -o json'
        )
        self.assertEqual(application.returncode, 0, application.stderr)
        self.assertEqual(json.loads(application.stdout)["metadata"]["name"], "legacy-erp")
        logs = self.run_command(
            'KCTL=kubectl\nNS=team-frontend\nCR=team-argocd\n'
            '"$KCTL" logs "statefulset/${CR}-application-controller" -n "$NS" --tail=50'
        )
        self.assertEqual(logs.returncode, 0, logs.stderr)
        self.assertIn("automated sync is not configured", logs.stdout)
        self.assertEqual(sum(e["event"] == "session" for e in self.events()), 2)
        self.assertEqual(sum(e["event"] == "cli" for e in self.events()), 2)

    def test_assignments_do_not_persist_between_sessions(self):
        first = self.run_command('KCTL=oc\n"$KCTL" config current-context')
        self.assertEqual(first.returncode, 0, first.stderr)
        second = self.run_command('"$KCTL" config current-context')
        self.assertEqual(second.returncode, 64)
        self.assertIn("KCTL is unset", second.stderr)
        self.assertEqual(second.stdout, "")

    def test_inherited_environment_and_path_are_not_used(self):
        marker = self.root / "host-client-was-run"
        client = self.root / "oc"
        client.write_text('#!/bin/sh\ntouch "' + str(marker) + '"\n')
        client.chmod(0o755)
        env = dict(os.environ, PATH=str(self.root), HOME=str(self.root),
                   KUBECONFIG="/tmp/never-read-offline-kubeconfig",
                   KCTL=str(client), NS="wrong-namespace")
        result = self.run_command(APP_READ, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["metadata"]["namespace"], "team-frontend")
        self.assertFalse(marker.exists())
        for variable in ("KUBECONFIG", "HOME", "PATH", "KCTL", "NS"):
            with self.subTest(variable=variable):
                result = self.run_command('oc get "$' + variable + '"', env=env)
                self.assertEqual(result.returncode, 64)
                self.assertNotIn("never-read-offline-kubeconfig", result.stdout + result.stderr)

    def test_absolute_executable_cannot_bypass_simulator(self):
        marker = self.root / "bypass-was-run"
        client = self.root / "alternate-kubectl"
        client.write_text('#!/bin/sh\ntouch "' + str(marker) + '"\n')
        client.chmod(0o755)
        for command in (str(client) + " get pods", f'KCTL={client}\n"$KCTL" get pods',
                        "/usr/bin/env oc get pods", "command oc get pods"):
            with self.subTest(command=command):
                result = self.run_command(command)
                self.assertEqual(result.returncode, 64)
                self.assertEqual(result.stdout, "")
                self.assertFalse(marker.exists())

    def test_shell_operators_and_substitutions_fail_closed(self):
        marker = self.root / "substitution-was-run"
        for command in (f'KCTL=$(touch {marker})\n{APP_READ}',
                        f'KCTL=`touch {marker}`\n{APP_READ}',
                        APP_READ + f"; touch {marker}",
                        APP_READ + " | cat", APP_READ + f" > {marker}",
                        "if true; then " + APP_READ + "; fi",
                        APP_READ + " && " + LOG_READ):
            with self.subTest(command=command):
                result = self.run_command(command)
                self.assertEqual(result.returncode, 64)
                self.assertEqual(result.stdout, "")
                self.assertFalse(marker.exists())
        self.assertFalse(any(e["event"] == "cli" for e in self.events()))

    def test_unsupported_operations_have_no_partial_success(self):
        for command in ("oc patch argocd team-argocd -n team-frontend --type=merge",
                        "oc get pods -n team-frontend", APP_READ + " --server=https://example.test",
                        APP_READ + "\noc delete namespace team-frontend",
                        "oc get argocd -o json", "oc api-resources --server=https://example.test"):
            with self.subTest(command=command):
                result = self.run_command(command)
                self.assertEqual(result.returncode, 64)
                self.assertEqual(result.stdout, "")
        self.assertFalse(any(e["event"] == "cli" for e in self.events()))

    def test_discovery_and_reordered_supported_flags(self):
        result = self.run_command("oc config current-context\noc api-resources --api-group=route.openshift.io\noc get -o json argocd -A")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("offline-fixture", result.stdout)
        self.assertIn("route.openshift.io/v1", result.stdout)
        self.assertEqual(json.loads(result.stdout.splitlines()[-1])["items"][0]["metadata"]["name"], "team-argocd")
        result = self.run_command("kubectl get -o json --namespace team-frontend applications.argoproj.io legacy-erp")
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
