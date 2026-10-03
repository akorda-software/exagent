"""Offline release guards against actual temporary Git histories; no Hex writes."""

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

CHECK = Path(__file__).resolve().parents[2] / "bin/release-check"
WORKFLOW = CHECK.parent.parent / ".github/workflows/release.yml"


class ReleaseCheckTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="exagent-release-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.write("mix.exs", '@version "2.0.0"\n')
        self.write("docs/changelog.md", "# Changelog\n\n## [2.0.0]\n")
        for name in ["README.md", "docs/home.md", "docs/README.md", "docs/status.md",
                     "docs/guides/getting-started.md", "docs/guides/agents.md",
                     "docs/guides/migration.md"]:
            self.write(name, "# ExAgent 2.0\n")
        self.git("init", "--quiet", "--initial-branch=main")
        self.commit()
        self.git("tag", "v2.0.0")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def git(self, *args):
        result = subprocess.run(["git", *args], cwd=self.root,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def commit(self):
        self.git("add", ".")
        self.git("-c", "user.name=Release Test", "-c", "user.email=release@example.invalid",
                 "commit", "--quiet", "-m", "fixture")

    def run_check(self, *args, success=False, reason=None):
        result = subprocess.run(["python3", str(CHECK), *args], cwd=self.root,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if success else 1, result.stderr)
        if reason:
            self.assertIn(reason, result.stderr)
        return result

    def test_stable_merged_tag(self):
        result = self.run_check("v2.0.0", success=True)
        self.assertEqual(json.loads(result.stdout)["mode"], "merged-tag")

    def test_prerelease_build_suffix_and_noncanonical_versions(self):
        for tag in ["v2.0.0-rc.1", "v2.0.0+build", "2.0.0", "v02.0.0", "v2.0.0\n"]:
            with self.subTest(tag=tag):
                self.run_check(tag, reason="stable tag")

    def test_tag_version_mismatch(self):
        self.run_check("v2.0.1", reason="single @version")

    def test_missing_release_notes(self):
        self.write("docs/changelog.md", "## [Unreleased]\n")
        self.run_check("v2.0.0", reason="release heading")

    def test_stale_candidate_introduction(self):
        self.write("docs/home.md", "These describe the unreleased v2 candidate.\n")
        self.run_check("v2.0.0", reason="introduction in docs/home.md")

    def test_stale_documentation_footer(self):
        self.write("mix.exs", '@version "2.0.0"\nfooter = "Unreleased v2 candidate"\n')
        self.run_check("v2.0.0", reason="documentation footer")

    def test_uncommitted_changes(self):
        self.write("README.md", "Changed release docs\n")
        self.run_check("v2.0.0", reason="must be clean")

    def test_missing_tag(self):
        self.git("tag", "--delete", "v2.0.0")
        self.run_check("v2.0.0", reason="refs/tags/v2.0.0")

    def test_tag_points_to_different_commit(self):
        self.write("README.md", "New commit\n")
        self.commit()
        self.run_check("v2.0.0", reason="checked-out commit")

    def test_commit_not_merged_to_main(self):
        self.write("README.md", "Branch-only release\n")
        self.commit()
        self.git("tag", "--force", "v2.0.0")
        self.run_check("v2.0.0", reason="merge-base --is-ancestor")

    def test_preparation_does_not_claim_merged_tag(self):
        self.git("tag", "--delete", "v2.0.0")
        self.write("README.md", "Metadata under preparation\n")
        result = self.run_check("v2.0.0", "--prepare", success=True)
        self.assertEqual(json.loads(result.stdout)["mode"], "metadata-only")


class PublicationRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="exagent-publish-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git_root = self.root / "checkout"
        self.git_root.mkdir()
        subprocess.run(["git", "init", "--quiet", str(self.git_root)], check=True)
        package = self.root / "exagent-release"
        package.mkdir()
        (package / "exagent.tar").write_bytes(b"frozen release bytes")
        executable = self.root / "bin"
        executable.mkdir()
        fake = executable / "elixir"
        fake.write_text('#!/bin/sh\nprintf "%s\\n" "$*" > "$FAKE_PUBLISH_CALL"\n'
                        'exit "${FAKE_PUBLISH_EXIT:-0}"\n')
        fake.chmod(0o700)
        self.call = self.root / "publish-call"
        self.env = dict(os.environ, PATH=str(executable) + ":" + os.environ["PATH"],
                        HEX_API_KEY="test-only-key", RELEASE_VERSION="2.0.0",
                        RUNNER_TEMP=str(self.root), FAKE_PUBLISH_CALL=str(self.call))
        section = WORKFLOW.read_text().split(
            "      - name: Publish package and documentation to Hex\n", 1)[1]
        section = section.split("        run: |\n", 1)[1].split("\n      - name:", 1)[0]
        self.script = "set -euo pipefail\n" + "\n".join(
            line[10:] for line in section.splitlines())
        self.requests = []

    def serve(self, status, body):
        requests = self.requests

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                self.send_response(status)
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        self.addCleanup(worker.join, 2)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return f"http://127.0.0.1:{server.server_address[1]}"

    def run_publication(self, status=404, body=b"", success=True):
        origin = self.serve(status, body)
        # Execute the actual workflow shell, with only its public CDN replaced
        # by a loopback fixture and the native publishing CLI replaced by a recorder.
        script = self.script.replace("https://repo.hex.pm", origin)
        result = subprocess.run(["bash", "-c", script], cwd=self.git_root,
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        self.assertNotIn("test-only-key", result.stdout + result.stderr)
        return result

    def test_missing_package_publishes_package_and_docs(self):
        self.run_publication()
        self.assertTrue(self.call.read_text().strip().endswith("-- hex.publish --yes"))
        self.assertEqual(self.requests, ["/tarballs/exagent-2.0.0.tar"])

    def test_identical_package_recovers_docs_without_replacing_package(self):
        self.run_publication(200, b"frozen release bytes")
        self.assertTrue(self.call.read_text().strip().endswith("-- hex.publish docs --yes"))

    def test_different_published_package_never_calls_publisher(self):
        self.run_publication(200, b"different package", success=False)
        self.assertFalse(self.call.exists())

    def test_server_failure_never_treats_package_as_absent(self):
        self.run_publication(503, success=False)
        self.assertFalse(self.call.exists())

    def test_missing_key_fails_before_network_or_publication(self):
        self.env["HEX_API_KEY"] = ""
        self.run_publication(success=False)
        self.assertFalse(self.requests)
        self.assertFalse(self.call.exists())

    def test_publisher_failure_propagates(self):
        self.env["FAKE_PUBLISH_EXIT"] = "42"
        result = self.run_publication(success=False)
        self.assertEqual(result.returncode, 42)


if __name__ == "__main__":
    unittest.main()
